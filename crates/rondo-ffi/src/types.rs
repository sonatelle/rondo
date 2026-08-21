//! How the core's value types cross the language boundary.
//!
//! All of them travel as their canonical string form rather than a numeric
//! type: exact, self-describing, and identical to what the database and the
//! backup file already hold, so one representation serves every layer.
//!
//! The money rule is the one that must not bend. A `Decimal` crossing as a
//! double would be rounded to the nearest binary fraction, and 15.99 does
//! not have one - the amount would arrive subtly wrong and no test on
//! either side would see it happen.
//!
//! `Uuid` and `Timestamp` keep their own names on the far side, since
//! neither collides with anything in Foundation. `Decimal` and `Date` do
//! collide, and the generated Swift declares a type per Rust type name, so
//! for those two the core type is wrapped in a differently named one here.
//! Without that, every bare `Date` in the app would be ambiguous against
//! `Foundation.Date`.

use jiff::Timestamp;
use jiff::civil::Date;
use rust_decimal::Decimal;
use uuid::Uuid;

uniffi::custom_type!(Uuid, String, {
    remote,
    lower: |value| value.to_string(),
    try_lift: |value| Ok(value.parse()?),
});

uniffi::custom_type!(Timestamp, String, {
    remote,
    lower: |value| value.to_string(),
    try_lift: |value| Ok(value.parse()?),
});

/// An exact decimal amount, carried as text.
///
/// Named apart from `Decimal` so the generated Swift does not shadow
/// `Foundation.Decimal`. Parse it before doing arithmetic; the string is
/// the exact value, not an approximation of it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DecimalString(pub Decimal);

uniffi::custom_type!(DecimalString, String, {
    lower: |value| value.0.to_string(),
    try_lift: |value| Ok(DecimalString(value.parse()?)),
});

/// A calendar date with no time zone, carried as `YYYY-MM-DD`.
///
/// Named apart from `Date` for the same reason as [`DecimalString`], and
/// because the distinction matters: a billing date is a day on a calendar,
/// not the instant `Foundation.Date` represents.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CivilDate(pub Date);

uniffi::custom_type!(CivilDate, String, {
    lower: |value| value.0.to_string(),
    try_lift: |value| Ok(CivilDate(value.parse()?)),
});

#[cfg(test)]
mod tests {
    use super::*;
    use std::str::FromStr;

    /// Asserts the string form survives a round trip unchanged.
    fn round_trips<T>(text: &str)
    where
        T: FromStr + ToString,
        T::Err: std::fmt::Debug,
    {
        let value = T::from_str(text).expect("the sample should parse");
        assert_eq!(value.to_string(), text);
    }

    #[test]
    fn every_boundary_type_round_trips_through_its_string_form() {
        round_trips::<Uuid>("01a021fd-60be-7ab0-9393-ace2baf29b85");
        round_trips::<Timestamp>("2026-08-21T00:00:00Z");
        let date = CivilDate(Date::from_str("2026-01-31").unwrap());
        assert_eq!(date.0.to_string(), "2026-01-31");
    }

    #[test]
    fn amounts_keep_their_scale_across_the_boundary() {
        // A trailing zero is meaningful for money: 15.90 is a price, 15.9
        // is a number. The string form preserves it; a double would not.
        for text in ["15.90", "0.001", "15.99"] {
            let amount = DecimalString(Decimal::from_str(text).unwrap());
            assert_eq!(amount.0.to_string(), text);
        }
    }

    #[test]
    fn malformed_input_from_the_foreign_side_is_rejected() {
        assert!(Uuid::from_str("not-a-uuid").is_err());
        assert!(Timestamp::from_str("yesterday").is_err());
        assert!(Decimal::from_str("fifteen").is_err());
        assert!(Date::from_str("2026-02-30").is_err());
    }
}
