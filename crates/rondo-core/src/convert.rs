//! Converting an amount into another currency at the rate of its own day.
//!
//! Every rate is quoted against [`BASE_CURRENCY`], so a conversion between
//! two other currencies goes through it. The base itself is never stored:
//! one unit of it is one unit of it, on every day there has ever been.

use std::collections::HashMap;

use jiff::civil::Date;
use rust_decimal::Decimal;

use crate::error::{Error, Result};
use crate::model::{BASE_CURRENCY, ExchangeRate, Money, rate_on};

/// Exchange-rate histories by currency, each sorted by effective day.
///
/// This is the shape [`crate::store::Store::all_rates`] returns. Converting
/// many amounts walks these in memory rather than asking the database once
/// per charge, which is what a year of daily totals would otherwise do.
pub type RateHistories = HashMap<String, Vec<ExchangeRate>>;

/// Converts `money` into `to` at the rate in force on `on`.
///
/// Returns `Ok(None)` when no rate can be found for either currency on that
/// day - which happens whenever a charge predates the stored history. That
/// is a real answer and the caller must report it as such: falling back to
/// 1:1 would produce a wrong number indistinguishable from a right one.
///
/// Amounts already in `to` are returned unchanged without consulting any
/// rate, so a database with no rates at all still totals correctly for
/// somebody whose subscriptions are all in one currency.
pub fn convert(rates: &RateHistories, money: &Money, to: &str, on: Date) -> Result<Option<Money>> {
    if money.currency() == to {
        return Ok(Some(money.clone()));
    }
    let (Some(from_rate), Some(to_rate)) = (
        rate_for(rates, money.currency(), on),
        rate_for(rates, to, on),
    ) else {
        return Ok(None);
    };

    // Multiply before dividing, so the single division happens last and
    // there is only one place for a repeating decimal to be truncated.
    // Dividing first is measurably worse: 100 USD to CNY comes back as
    // 750.00000000000000000000000001 that way and as exactly 750 this way.
    let converted = money
        .amount()
        .checked_mul(to_rate)
        .and_then(|scaled| scaled.checked_div(from_rate))
        .ok_or_else(|| {
            Error::InvalidRate(format!(
                "converting {} {} to {to} at {from_rate}/{to_rate} left the decimal range",
                money.amount(),
                money.currency(),
            ))
        })?;
    Ok(Some(Money::new(converted, to)?))
}

/// Units of `currency` per one unit of the base, in force on `on`.
///
/// The base is not in the table and does not need to be: it is 1 against
/// itself by definition.
fn rate_for(rates: &RateHistories, currency: &str, on: Date) -> Option<Decimal> {
    if currency == BASE_CURRENCY {
        return Some(Decimal::ONE);
    }
    rate_on(rates.get(currency)?, on).map(|rate| rate.rate)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::str::FromStr;

    const DAY: Date = Date::constant(2026, 9, 7);

    fn dec(value: &str) -> Decimal {
        Decimal::from_str(value).unwrap()
    }

    fn money(amount: &str, currency: &str) -> Money {
        Money::new(dec(amount), currency).unwrap()
    }

    /// One EUR bought 8.25 CNY and 1.10 USD on 2026-09-04, and nothing is
    /// recorded before that day.
    fn rates() -> RateHistories {
        let mut rates = RateHistories::new();
        for (currency, rate) in [("CNY", "8.25"), ("USD", "1.10")] {
            rates.insert(
                currency.to_owned(),
                vec![
                    ExchangeRate::new(currency, Date::constant(2026, 9, 4), dec(rate), false)
                        .unwrap(),
                ],
            );
        }
        rates
    }

    #[test]
    fn an_amount_already_in_the_target_currency_needs_no_rate() {
        let empty = RateHistories::new();
        assert_eq!(
            convert(&empty, &money("15.99", "USD"), "USD", DAY).unwrap(),
            Some(money("15.99", "USD"))
        );
    }

    #[test]
    fn the_base_currency_is_one_against_itself() {
        // EUR is never stored, so this can only work if conversion knows it.
        let converted = convert(&rates(), &money("10", "EUR"), "CNY", DAY)
            .unwrap()
            .unwrap();
        assert_eq!(converted, money("82.50", "CNY"));

        let back = convert(&rates(), &money("82.50", "CNY"), "EUR", DAY)
            .unwrap()
            .unwrap();
        assert_eq!(back.amount(), dec("10"));
    }

    #[test]
    fn two_non_base_currencies_convert_through_the_base() {
        // 11 USD is 10 EUR is 82.50 CNY.
        let converted = convert(&rates(), &money("11", "USD"), "CNY", DAY)
            .unwrap()
            .unwrap();
        assert_eq!(converted.amount(), dec("82.5"));
        assert_eq!(converted.currency(), "CNY");
    }

    #[test]
    fn an_amount_that_does_not_divide_evenly_still_lands_exactly() {
        // 100 is deliberately not a multiple of 1.10. Divide first and this
        // comes back as 750.00000000000000000000000001; multiplying first
        // leaves the one division until last and it is exactly 750.
        //
        // The test above cannot catch that: 11 divides by 1.10 evenly, so
        // both orders agree on it.
        let converted = convert(&rates(), &money("100", "USD"), "CNY", DAY)
            .unwrap()
            .unwrap();
        assert_eq!(converted.amount(), dec("750"));
    }

    #[test]
    fn a_charge_older_than_every_rate_is_not_converted() {
        let before = Date::constant(2026, 9, 3);
        assert_eq!(
            convert(&rates(), &money("11", "USD"), "CNY", before).unwrap(),
            None
        );
        // And emphatically not 1:1, which is the tempting wrong answer.
        assert_ne!(
            convert(&rates(), &money("11", "USD"), "CNY", before).unwrap(),
            Some(money("11", "CNY"))
        );
    }

    #[test]
    fn a_currency_with_no_history_at_all_is_not_converted() {
        assert_eq!(
            convert(&rates(), &money("100", "JPY"), "CNY", DAY).unwrap(),
            None
        );
        assert_eq!(
            convert(&rates(), &money("11", "USD"), "JPY", DAY).unwrap(),
            None
        );
    }

    #[test]
    fn a_rate_holds_forward_over_days_the_source_skipped() {
        // The stored rate is Friday's; this asks about the Monday after.
        let converted = convert(
            &rates(),
            &money("11", "USD"),
            "CNY",
            Date::constant(2026, 9, 7),
        )
        .unwrap()
        .unwrap();
        assert_eq!(converted.amount(), dec("82.5"));
    }

    #[test]
    fn conversion_keeps_more_precision_than_it_will_ever_show() {
        // 10 / 8.25 * 1.10 does not terminate. Rounding belongs at
        // presentation, so what comes back here is not rounded to cents.
        let converted = convert(&rates(), &money("10", "CNY"), "USD", DAY)
            .unwrap()
            .unwrap();
        assert!(
            converted.amount().scale() > 2,
            "{} was rounded too early",
            converted.amount()
        );
        // Converting back lands within a cent of where it started.
        let back = convert(&rates(), &converted, "CNY", DAY).unwrap().unwrap();
        assert!((back.amount() - dec("10")).abs() < dec("0.01"));
    }

    #[test]
    fn zero_converts_to_zero_rather_than_failing() {
        let converted = convert(&rates(), &money("0", "USD"), "CNY", DAY)
            .unwrap()
            .unwrap();
        assert_eq!(converted.amount(), Decimal::ZERO);
    }
}
