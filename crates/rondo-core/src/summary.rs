//! Spending normalization and per-currency summaries.
//!
//! Normalization convention: a year is 365.25 days (accounting for leap
//! years) and a month is exactly 1/12 of a year. Month- and year-based
//! cycles divide exactly; day- and week-based cycles are approximations by
//! nature. Results keep full decimal precision - round only for display.

use std::collections::BTreeMap;

use jiff::civil::Date;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::{Error, Result};
use crate::model::{
    BillingCycle, CycleUnit, Money, Price, Subscription, SubscriptionStatus, price_on,
};

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

/// One charge that fell due, and what it cost that day.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Charge {
    /// The day the charge fell due.
    pub date: Date,
    /// What was charged, at the price in force on that day.
    pub amount: Money,
}

/// Every charge a subscription falls due for in the half-open range
/// `[from, to)`, each priced at the entry in force on its own day.
///
/// This is the primitive the other totals are built from, so that a
/// cumulative, a month's bar and a year-to-date can never disagree about
/// what a given charge cost. Pricing charge by charge is the whole reason
/// the price became a history: multiplying today's price by the number of
/// charges is wrong by every rise that ever happened.
///
/// The range is not clipped to today. A caller wanting only what has
/// actually been charged passes tomorrow as `to`; one drawing a forecast
/// passes a date further out.
pub fn charges(sub: &Subscription, history: &[Price], from: Date, to: Date) -> Result<Vec<Charge>> {
    let dates = crate::cycle::occurrences_between(sub.first_billing_date, sub.cycle, from, to)?;
    dates
        .into_iter()
        .map(|date| {
            let price = price_on(history, date)
                .ok_or_else(|| Error::Corrupt(format!("subscription {} has no price", sub.id)))?;
            Ok(Charge {
                date,
                amount: price.amount.clone(),
            })
        })
        .collect()
}

/// What one subscription has cost so far, and over how many charges.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubscriptionTotal {
    pub subscription_id: Uuid,
    /// Currency of every charge counted; a subscription has only one.
    pub currency: String,
    /// Sum of every charge in the window, at the price each was charged at.
    pub total: Decimal,
    /// How many charges that sum covers.
    pub charge_count: u32,
    /// The first and last charge counted, absent when there were none.
    pub first_charge: Option<Date>,
    pub last_charge: Option<Date>,
}

/// Totals what a subscription has cost from its first charge up to but not
/// including `until`.
///
/// Pass tomorrow to count everything charged so far; pass a later date to
/// include charges still to come.
pub fn subscription_total(
    sub: &Subscription,
    history: &[Price],
    until: Date,
) -> Result<SubscriptionTotal> {
    let charges = charges(sub, history, sub.first_billing_date, until)?;
    Ok(SubscriptionTotal {
        subscription_id: sub.id,
        currency: sub.price.currency().to_owned(),
        total: charges.iter().map(|c| c.amount.amount()).sum(),
        charge_count: charges.len() as u32,
        first_charge: charges.first().map(|c| c.date),
        last_charge: charges.last().map(|c| c.date),
    })
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

    /// A history of one price, the shape every subscription has until
    /// somebody records a rise.
    fn one_price(sub: &Subscription) -> Vec<Price> {
        vec![Price {
            id: sub.id,
            subscription_id: sub.id,
            effective_from: sub.first_billing_date,
            amount: sub.price.clone(),
            created_at: sub.created_at,
            updated_at: sub.updated_at,
        }]
    }

    #[test]
    fn charges_fall_on_the_anchored_days() {
        let s = sub("Netflix", money("10.00", "USD"), cycle(1, CycleUnit::Month));
        let found = charges(
            &s,
            &one_price(&s),
            Date::constant(2026, 1, 1),
            Date::constant(2026, 4, 1),
        )
        .unwrap();
        assert_eq!(
            found.iter().map(|c| c.date).collect::<Vec<_>>(),
            [
                Date::constant(2026, 1, 1),
                Date::constant(2026, 2, 1),
                Date::constant(2026, 3, 1)
            ],
            "the range is half-open, so April's charge is not in it"
        );
    }

    /// The reason the price became a history: a cumulative built from
    /// today's price is wrong by every rise that ever happened.
    #[test]
    fn a_total_prices_each_charge_at_the_price_of_its_own_day() {
        let s = sub("Netflix", money("10.00", "USD"), cycle(1, CycleUnit::Month));
        let mut history = one_price(&s);
        history.push(Price {
            id: Uuid::now_v7(),
            subscription_id: s.id,
            effective_from: Date::constant(2026, 3, 1),
            amount: money("15.00", "USD"),
            created_at: s.created_at,
            updated_at: s.updated_at,
        });

        // Charges on 1 January through 1 May: two at 10, three at 15.
        let total = subscription_total(&s, &history, Date::constant(2026, 6, 1)).unwrap();
        assert_eq!(total.charge_count, 5);
        assert_eq!(total.total, Decimal::from_str("65.00").unwrap());
        assert_eq!(total.first_charge, Some(Date::constant(2026, 1, 1)));
        assert_eq!(total.last_charge, Some(Date::constant(2026, 5, 1)));

        // The naive answer, which this exists to avoid.
        assert_ne!(total.total, Decimal::from_str("75.00").unwrap());
    }

    #[test]
    fn a_subscription_whose_first_charge_has_not_arrived_has_cost_nothing() {
        let mut s = sub("Grok", money("700", "INR"), cycle(1, CycleUnit::Month));
        s.first_billing_date = Date::constant(2026, 9, 18);
        let total = subscription_total(&s, &one_price(&s), Date::constant(2026, 9, 3)).unwrap();
        assert_eq!(total.charge_count, 0);
        assert_eq!(total.total, Decimal::ZERO);
        assert!(total.first_charge.is_none());
        // The currency is still knowable, so a screen can say "US$0.00"
        // rather than having nothing to say.
        assert_eq!(total.currency, "INR");
    }

    /// Month-end anchoring has to survive being counted, not just being
    /// scheduled: a charge anchored to the 31st is one charge in February.
    #[test]
    fn month_end_charges_are_counted_once_each() {
        let mut s = sub("Anchored", money("1.00", "USD"), cycle(1, CycleUnit::Month));
        s.first_billing_date = Date::constant(2026, 1, 31);
        let found = charges(
            &s,
            &one_price(&s),
            Date::constant(2026, 1, 1),
            Date::constant(2026, 5, 1),
        )
        .unwrap();
        assert_eq!(
            found.iter().map(|c| c.date).collect::<Vec<_>>(),
            [
                Date::constant(2026, 1, 31),
                Date::constant(2026, 2, 28),
                Date::constant(2026, 3, 31),
                Date::constant(2026, 4, 30),
            ]
        );
    }
}
