//! Spending normalization and per-currency summaries.
//!
//! Normalization convention: a year is 365.25 days (accounting for leap
//! years) and a month is exactly 1/12 of a year. Month- and year-based
//! cycles divide exactly; day- and week-based cycles are approximations by
//! nature. Results keep full decimal precision - round only for display.

use std::collections::BTreeMap;

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};

use crate::model::{BillingCycle, CycleUnit, Money, Subscription, SubscriptionStatus};

/// Days in an average calendar year under this module's convention.
const DAYS_PER_YEAR: Decimal = Decimal::from_parts(36525, 0, 0, false, 2);

/// Months in a year, exact.
const MONTHS_PER_YEAR: Decimal = Decimal::from_parts(12, 0, 0, false, 0);

/// Days in a week, exact.
const DAYS_PER_WEEK: Decimal = Decimal::from_parts(7, 0, 0, false, 0);

/// Cost of one subscription normalized to a year.
///
/// `price` is charged once per `cycle`; see the module docs for the
/// normalization convention.
pub fn yearly_cost(price: &Money, cycle: BillingCycle) -> Decimal {
    let count = Decimal::from(cycle.count());
    let amount = price.amount();
    match cycle.unit() {
        CycleUnit::Day => amount * DAYS_PER_YEAR / count,
        CycleUnit::Week => amount * DAYS_PER_YEAR / (DAYS_PER_WEEK * count),
        CycleUnit::Month => amount * MONTHS_PER_YEAR / count,
        CycleUnit::Year => amount / count,
    }
}

/// Cost of one subscription normalized to a month (1/12 of [`yearly_cost`]).
pub fn monthly_cost(price: &Money, cycle: BillingCycle) -> Decimal {
    yearly_cost(price, cycle) / MONTHS_PER_YEAR
}

/// Total normalized spending for one currency.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SpendingSummary {
    /// Three-letter uppercase currency code the totals are denominated in.
    pub currency: String,
    /// Active subscriptions counted into the totals.
    pub subscription_count: u32,
    /// Total cost normalized to a month, full precision.
    pub monthly: Decimal,
    /// Total cost normalized to a year, full precision.
    pub yearly: Decimal,
}

/// Sums active subscriptions into one summary per currency.
///
/// Archived subscriptions are excluded. Currencies are never converted or
/// mixed; the result is sorted by currency code.
pub fn summarize(subscriptions: &[Subscription]) -> Vec<SpendingSummary> {
    let mut by_currency: BTreeMap<&str, SpendingSummary> = BTreeMap::new();
    for sub in subscriptions {
        if sub.status != SubscriptionStatus::Active {
            continue;
        }
        let entry = by_currency
            .entry(sub.price.currency())
            .or_insert_with(|| SpendingSummary {
                currency: sub.price.currency().to_owned(),
                subscription_count: 0,
                monthly: Decimal::ZERO,
                yearly: Decimal::ZERO,
            });
        entry.subscription_count += 1;
        entry.monthly += monthly_cost(&sub.price, sub.cycle);
        entry.yearly += yearly_cost(&sub.price, sub.cycle);
    }
    by_currency.into_values().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::BillingCycle;
    use jiff::civil::Date;
    use std::str::FromStr;

    fn money(s: &str, currency: &str) -> Money {
        Money::new(Decimal::from_str(s).unwrap(), currency).unwrap()
    }

    fn cycle(count: u32, unit: CycleUnit) -> BillingCycle {
        BillingCycle::new(count, unit).unwrap()
    }

    fn sub(name: &str, price: Money, cycle: BillingCycle) -> Subscription {
        Subscription::new(name, price, cycle, Date::constant(2026, 1, 1)).unwrap()
    }

    #[test]
    fn monthly_and_yearly_cycles_normalize_exactly() {
        let monthly = money("12.00", "USD");
        assert_eq!(
            yearly_cost(&monthly, cycle(1, CycleUnit::Month)),
            Decimal::from_str("144.00").unwrap()
        );
        let yearly = money("120.00", "USD");
        assert_eq!(
            monthly_cost(&yearly, cycle(1, CycleUnit::Year)),
            Decimal::from_str("10").unwrap()
        );
        // Every-three-months divides the rate, not multiplies it.
        assert_eq!(
            yearly_cost(&monthly, cycle(3, CycleUnit::Month)),
            Decimal::from_str("48.00").unwrap()
        );
    }

    #[test]
    fn week_cycles_use_the_average_year() {
        let weekly = money("7.00", "EUR");
        // 7.00 * 365.25 / 7 = 365.25 per year.
        assert_eq!(
            yearly_cost(&weekly, cycle(1, CycleUnit::Week)),
            Decimal::from_str("365.25").unwrap()
        );
    }

    #[test]
    fn summarize_groups_by_currency_and_skips_archived() {
        let mut subs = vec![
            sub("a", money("10.00", "USD"), cycle(1, CycleUnit::Month)),
            sub("b", money("120.00", "USD"), cycle(1, CycleUnit::Year)),
            sub("c", money("5.00", "EUR"), cycle(1, CycleUnit::Month)),
            sub("d", money("99.00", "USD"), cycle(1, CycleUnit::Month)),
        ];
        subs[3].status = SubscriptionStatus::Archived;

        let summaries = summarize(&subs);
        assert_eq!(summaries.len(), 2);
        // BTreeMap ordering: EUR before USD.
        assert_eq!(summaries[0].currency, "EUR");
        assert_eq!(summaries[0].subscription_count, 1);
        assert_eq!(summaries[1].currency, "USD");
        assert_eq!(summaries[1].subscription_count, 2);
        assert_eq!(summaries[1].monthly, Decimal::from_str("20").unwrap());
        assert_eq!(summaries[1].yearly, Decimal::from_str("240.00").unwrap());
    }

    #[test]
    fn empty_input_produces_no_summaries() {
        assert!(summarize(&[]).is_empty());
    }
}
