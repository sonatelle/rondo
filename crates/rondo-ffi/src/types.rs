//! How the core's value types cross the language boundary.
//!
//! Each of these is defined in another crate, so UniFFI needs to be told
//! how to carry it. All four travel as their canonical string form rather
//! than a numeric type: exact, self-describing, and identical to what the
//! database and the backup file already hold, so one representation serves
//! every layer.
//!
//! The money rule is the one that must not bend. A `Decimal` crossing as a
//! double would be rounded to the nearest binary fraction, and 15.99 does
//! not have one - the amount would arrive subtly wrong and no test on
//! either side would see it happen.

use jiff::Timestamp;
use jiff::civil::Date;
use rust_decimal::Decimal;
use uuid::Uuid;

uniffi::custom_type!(Uuid, String, {
    remote,
    lower: |value| value.to_string(),
    try_lift: |value| Ok(value.parse()?),
});

uniffi::custom_type!(Decimal, String, {
    remote,
    lower: |value| value.to_string(),
    try_lift: |value| Ok(value.parse()?),
});

uniffi::custom_type!(Date, String, {
    remote,
    lower: |value| value.to_string(),
    try_lift: |value| Ok(value.parse()?),
});

uniffi::custom_type!(Timestamp, String, {
    remote,
    lower: |value| value.to_string(),
    try_lift: |value| Ok(value.parse()?),
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
        round_trips::<Date>("2026-01-31");
        round_trips::<Timestamp>("2026-08-21T00:00:00Z");
    }

    #[test]
    fn amounts_keep_their_scale_across_the_boundary() {
        // A trailing zero is meaningful for money: 15.90 is a price, 15.9
        // is a number. The string form preserves it; a double would not.
        round_trips::<Decimal>("15.90");
        round_trips::<Decimal>("0.001");
        // The value a double cannot hold exactly, spelled out.
        let exact = Decimal::from_str("15.99").unwrap();
        assert_eq!(exact.to_string(), "15.99");
    }

    #[test]
    fn malformed_input_from_the_foreign_side_is_rejected() {
        assert!(Uuid::from_str("not-a-uuid").is_err());
        assert!(Decimal::from_str("fifteen").is_err());
        assert!(Date::from_str("2026-02-30").is_err());
        assert!(Timestamp::from_str("yesterday").is_err());
    }
}
