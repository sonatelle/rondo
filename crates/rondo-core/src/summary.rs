//! Spending normalization and per-currency summaries.
//!
//! Normalization convention: a year is 365.25 days (accounting for leap
//! years) and a month is exactly 1/12 of a year. Month- and year-based
//! cycles divide exactly; day- and week-based cycles are approximations by
//! nature. Results keep full decimal precision - round only for display.

use std::collections::{BTreeMap, HashMap};

use jiff::civil::Date;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::convert::{RateHistories, convert, pair_rate};
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

/// What one month cost, in one currency, read two ways.
///
/// Both readings are here because both questions get asked and they have
/// different answers. A yearly subscription lands its whole price in one
/// month and nothing in the other eleven; `charged` says so, and `levelled`
/// spreads it. Neither is more correct - a screen asking "what will my card
/// be charged" wants the first, and one asking "what do I spend a month"
/// wants the second.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MonthlySpending {
    /// First day of the month this covers.
    pub month: Date,
    /// Three-letter uppercase currency code.
    pub currency: String,
    /// What actually falls due this month, at the prices of the days it
    /// falls due on.
    pub charged: Decimal,
    /// The same subscriptions' cost spread evenly across their cycles, so
    /// a yearly plan contributes a twelfth each month.
    pub levelled: Decimal,
    /// How many charges make up `charged`.
    pub charge_count: u32,
}

/// Month-by-month spending across `[from, to)`, one entry per month and
/// currency, in month then currency order.
///
/// Months with nothing in them are present with zeros, so a chart can be
/// drawn straight from this without filling gaps itself - and so a month
/// that genuinely cost nothing is visible rather than missing.
///
/// **Archived subscriptions are left out entirely.** Rondo does not record
/// when a subscription was archived, so it cannot say which months it
/// belonged to; counting it in every month would overstate the past and
/// counting it in none understates it. Leaving it out is the smaller
/// error and the one that matches [`summarize`].
pub fn monthly_series(
    subscriptions: &[Subscription],
    histories: &HashMap<Uuid, Vec<Price>>,
    from: Date,
    to: Date,
) -> Result<Vec<MonthlySpending>> {
    let mut by_month: BTreeMap<(Date, String), MonthlySpending> = BTreeMap::new();
    let mut month = first_of_month(from);
    while month < to {
        for sub in subscriptions {
            if sub.status != SubscriptionStatus::Active {
                continue;
            }
            by_month
                .entry((month, sub.price.currency().to_owned()))
                .or_insert_with(|| MonthlySpending {
                    month,
                    currency: sub.price.currency().to_owned(),
                    charged: Decimal::ZERO,
                    levelled: Decimal::ZERO,
                    charge_count: 0,
                });
        }
        month = next_month(month);
    }

    for sub in subscriptions {
        if sub.status != SubscriptionStatus::Active {
            continue;
        }
        let history = histories
            .get(&sub.id)
            .map(Vec::as_slice)
            .unwrap_or_default();
        for charge in charges(sub, history, from, to)? {
            let key = (first_of_month(charge.date), sub.price.currency().to_owned());
            if let Some(entry) = by_month.get_mut(&key) {
                entry.charged += charge.amount.amount();
                entry.charge_count += 1;
            }
        }

        // Levelled spending starts the month of the first charge: before
        // that the subscription was not being paid for, and spreading its
        // cost backwards would invent history.
        let starts = first_of_month(sub.first_billing_date);
        let mut month = first_of_month(from).max(starts);
        while month < to {
            let price = price_on(history, month)
                .ok_or_else(|| Error::Corrupt(format!("subscription {} has no price", sub.id)))?;
            if let Some(entry) = by_month.get_mut(&(month, sub.price.currency().to_owned())) {
                entry.levelled += monthly_cost(&price.amount, sub.cycle);
            }
            month = next_month(month);
        }
    }

    Ok(by_month.into_values().collect())
}

/// What one category costs a month, in one currency.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CategoryShare {
    /// The category, or `None` for subscriptions filed under nothing.
    pub category_id: Option<Uuid>,
    /// Three-letter uppercase currency code.
    pub currency: String,
    /// Levelled monthly cost of the subscriptions in this category, so a
    /// yearly plan counts as a twelfth rather than as a spike.
    pub monthly: Decimal,
    /// How many active subscriptions are in it.
    pub subscription_count: u32,
}

/// Levelled monthly cost per category and currency, largest share first
/// within each currency.
///
/// Levelled rather than charged, because a share is a question about
/// proportion - "how much of my spending is streaming" - and a yearly plan
/// that happens to fall this month would otherwise swallow the chart.
///
/// Uncategorized subscriptions are one group with no id rather than being
/// dropped: a share that does not add up to the whole is worse than one
/// with an "everything else" slice in it. Archived subscriptions are left
/// out, as everywhere else.
pub fn category_shares(subscriptions: &[Subscription], on: Date) -> Vec<CategoryShare> {
    let mut by_key: BTreeMap<(String, Option<Uuid>), CategoryShare> = BTreeMap::new();
    for sub in subscriptions {
        if sub.status != SubscriptionStatus::Active || sub.first_billing_date > on {
            continue;
        }
        let entry = by_key
            .entry((sub.price.currency().to_owned(), sub.category_id))
            .or_insert_with(|| CategoryShare {
                category_id: sub.category_id,
                currency: sub.price.currency().to_owned(),
                monthly: Decimal::ZERO,
                subscription_count: 0,
            });
        entry.monthly += monthly_cost(&sub.price, sub.cycle);
        entry.subscription_count += 1;
    }
    let mut shares: Vec<CategoryShare> = by_key.into_values().collect();
    // Currency first so the groups stay together, then largest share, then
    // by id so two equal shares keep a stable order between refreshes.
    shares.sort_by(|a, b| {
        a.currency
            .cmp(&b.currency)
            .then(b.monthly.cmp(&a.monthly))
            .then(a.category_id.cmp(&b.category_id))
    });
    shares
}

/// What has been spent over a window, per currency.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WindowTotal {
    pub currency: String,
    /// Sum of every charge in the window, at the prices they were charged
    /// at.
    pub total: Decimal,
    pub charge_count: u32,
}

/// Totals every charge falling in `[from, to)`, per currency.
///
/// Year to date is this from 1 January to tomorrow; all time is this from
/// the earliest first charge to tomorrow. Both are the same question over
/// different windows, so they are the same function.
pub fn window_totals(
    subscriptions: &[Subscription],
    histories: &HashMap<Uuid, Vec<Price>>,
    from: Date,
    to: Date,
) -> Result<Vec<WindowTotal>> {
    let mut by_currency: BTreeMap<String, WindowTotal> = BTreeMap::new();
    for sub in subscriptions {
        if sub.status != SubscriptionStatus::Active {
            continue;
        }
        let history = histories
            .get(&sub.id)
            .map(Vec::as_slice)
            .unwrap_or_default();
        for charge in charges(sub, history, from, to)? {
            let entry = by_currency
                .entry(sub.price.currency().to_owned())
                .or_insert_with(|| WindowTotal {
                    currency: sub.price.currency().to_owned(),
                    total: Decimal::ZERO,
                    charge_count: 0,
                });
            entry.total += charge.amount.amount();
            entry.charge_count += 1;
        }
    }
    Ok(by_currency.into_values().collect())
}

/// The earliest day any of these subscriptions was first charged.
///
/// The natural start of an all-time window; `None` when there is nothing
/// to total.
pub fn earliest_charge(subscriptions: &[Subscription]) -> Option<Date> {
    subscriptions
        .iter()
        .filter(|s| s.status == SubscriptionStatus::Active)
        .map(|s| s.first_billing_date)
        .min()
}

/// The first day of the month `date` falls in.
fn first_of_month(date: Date) -> Date {
    Date::new(date.year(), date.month(), 1).expect("the first of a month is always a date")
}

/// The first day of the month after the one `date` starts.
///
/// Only ever called on a first-of-month, so it cannot clamp: no month has
/// fewer than one day.
fn next_month(date: Date) -> Date {
    if date.month() == 12 {
        Date::new(date.year() + 1, 1, 1).expect("January is always a date")
    } else {
        Date::new(date.year(), date.month() + 1, 1).expect("the first of a month is always a date")
    }
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

/// Spending that could not be converted, kept in its own currency.
///
/// Present so a screen can say what it left out rather than quietly
/// understating a total. One entry per currency no rate could be found for.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Unconverted {
    /// The currency the amounts below are in.
    pub currency: String,
    /// Active subscriptions left out of the converted totals.
    pub subscription_count: u32,
    /// Their monthly total, in their own currency.
    pub monthly: Decimal,
    /// Their yearly total, in their own currency.
    pub yearly: Decimal,
}

/// One currency that went into a converted total, and at what rate.
///
/// A screen saying "including US$73.90 at 7.1240" reads it from here. That
/// sentence has to be the rate the sum actually used, so it is reported by
/// whatever did the summing rather than worked back out afterwards: a
/// figure derived twice is a figure that can disagree with itself.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Applied {
    /// The currency the amounts were billed in.
    pub currency: String,
    /// Subscriptions counted from this currency.
    pub subscription_count: u32,
    /// Their monthly total, before conversion, in their own currency.
    pub monthly: Decimal,
    /// Their yearly total, before conversion, in their own currency.
    pub yearly: Decimal,
    /// How many of the primary currency one unit of `currency` bought.
    ///
    /// The pair as somebody thinks in it, not as it is stored: rates are
    /// held against a fixed base, and this is that pair divided out. It is
    /// `None` for the primary currency itself, which is not converted and
    /// has no rate to name.
    pub rate: Option<Decimal>,
}

/// Normalized spending as one figure, plus whatever would not convert.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConvertedSpending {
    /// The currency `monthly` and `yearly` are in.
    pub currency: String,
    /// Active subscriptions counted into the totals.
    pub subscription_count: u32,
    /// Total cost normalized to a month, full precision.
    pub monthly: Decimal,
    /// Total cost normalized to a year, full precision.
    pub yearly: Decimal,
    /// What went into the total, by currency, sorted by code.
    ///
    /// Carries the rate each was converted at, so a footnote can name it.
    pub applied: Vec<Applied>,
    /// What was left out, by currency, sorted by code. Empty is the good
    /// case and the common one.
    pub unconverted: Vec<Unconverted>,
}

/// Sums active subscriptions into one figure in `primary`.
///
/// Amounts are grouped by their own currency and each group converted once,
/// rather than each subscription separately: one division per currency
/// truncates a repeating decimal in one place instead of in every row.
///
/// A currency with no rate on `on` is not converted and not guessed at. Its
/// group moves to [`ConvertedSpending::unconverted`] whole, so the total
/// stays a number that is true about the subscriptions it claims to cover.
///
/// `on` is the day whose rates to use. These are levelled figures about
/// what things cost now, so it is normally today rather than any charge's
/// own day.
pub fn summarize_in(
    subscriptions: &[Subscription],
    rates: &RateHistories,
    primary: &str,
    on: Date,
) -> Result<ConvertedSpending> {
    let mut converted = ConvertedSpending {
        currency: primary.to_owned(),
        subscription_count: 0,
        monthly: Decimal::ZERO,
        yearly: Decimal::ZERO,
        applied: Vec::new(),
        unconverted: Vec::new(),
    };
    for group in summarize(subscriptions) {
        let monthly = convert(
            rates,
            &Money::new(group.monthly, &group.currency)?,
            primary,
            on,
        )?;
        let yearly = convert(
            rates,
            &Money::new(group.yearly, &group.currency)?,
            primary,
            on,
        )?;
        // Both or neither: a month converted and a year not would be two
        // figures a reader would have no way to tell apart.
        match (monthly, yearly) {
            (Some(monthly), Some(yearly)) => {
                converted.subscription_count += group.subscription_count;
                converted.monthly += monthly.amount();
                converted.yearly += yearly.amount();
                converted.applied.push(Applied {
                    // The primary currency was not converted, so there is
                    // no rate to name and printing 1.0000 would suggest
                    // one had been looked up.
                    rate: if group.currency == primary {
                        None
                    } else {
                        pair_rate(rates, &group.currency, primary, on)?
                    },
                    currency: group.currency,
                    subscription_count: group.subscription_count,
                    monthly: group.monthly,
                    yearly: group.yearly,
                });
            }
            _ => converted.unconverted.push(Unconverted {
                currency: group.currency,
                subscription_count: group.subscription_count,
                monthly: group.monthly,
                yearly: group.yearly,
            }),
        }
    }
    Ok(converted)
}

/// What one subscription has cost, every charge converted at its own day.
///
/// This is where storing rates as a history earns itself: a subscription
/// billed through a year of moving rates is totalled at what each charge
/// actually cost, so the figure does not move when the market does.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConvertedTotal {
    pub subscription_id: Uuid,
    /// The currency `total` is in.
    pub currency: String,
    /// Sum of every charge that could be converted.
    pub total: Decimal,
    /// How many charges fell in the window.
    pub charge_count: u32,
    /// How many of those `total` actually covers. Less than `charge_count`
    /// when the history does not reach back to the earliest ones, which is
    /// what a screen must say rather than imply by a smaller number.
    pub converted_charge_count: u32,
    /// The first and last charge counted, absent when there were none.
    pub first_charge: Option<Date>,
    pub last_charge: Option<Date>,
}

/// Which day's rate a past charge is converted at.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RateBasis {
    /// Each charge at the rate of the day it fell due.
    ///
    /// What a past total should normally be: it is what the money actually
    /// cost, and it does not move when the market does.
    OwnDay,
    /// Every charge at one day's rate, whatever the day asked about is.
    ///
    /// Answers a different question - "what would all of this cost at
    /// today's rate" - and a total built this way *will* drift as rates
    /// move. Offered because the design offers it as a switch, and worth
    /// showing as the deliberate choice it is rather than the default.
    OneDay,
}

/// Totals one subscription in `primary`, converting charge by charge.
///
/// Charges from before the rate history begins are counted in
/// `charge_count` and left out of `total`; see [`ConvertedTotal`].
///
/// `basis` decides which day's rate each charge is converted at; see
/// [`RateBasis`]. With [`RateBasis::OneDay`] the day is `until`, the same
/// day the caller is looking at the total on.
pub fn subscription_total_in(
    sub: &Subscription,
    history: &[Price],
    rates: &RateHistories,
    primary: &str,
    until: Date,
    basis: RateBasis,
) -> Result<ConvertedTotal> {
    let charges = charges(sub, history, sub.first_billing_date, until)?;
    let mut total = Decimal::ZERO;
    let mut converted_charge_count = 0;
    for charge in &charges {
        let on = match basis {
            RateBasis::OwnDay => charge.date,
            RateBasis::OneDay => until,
        };
        if let Some(amount) = convert(rates, &charge.amount, primary, on)? {
            total += amount.amount();
            converted_charge_count += 1;
        }
    }
    Ok(ConvertedTotal {
        subscription_id: sub.id,
        currency: primary.to_owned(),
        total,
        charge_count: charges.len() as u32,
        converted_charge_count,
        first_charge: charges.first().map(|c| c.date),
        last_charge: charges.last().map(|c| c.date),
    })
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

    fn histories_of(subs: &[Subscription]) -> HashMap<Uuid, Vec<Price>> {
        subs.iter().map(|s| (s.id, one_price(s))).collect()
    }

    /// The two readings answer different questions, and a yearly plan is
    /// where they part company: one month holds the whole charge, and every
    /// month holds a twelfth.
    #[test]
    fn a_yearly_plan_lands_in_one_month_and_levels_across_all_of_them() {
        let mut yearly = sub("Adobe", money("120.00", "USD"), cycle(1, CycleUnit::Year));
        yearly.first_billing_date = Date::constant(2026, 3, 15);
        let subs = [yearly];

        let series = monthly_series(
            &subs,
            &histories_of(&subs),
            Date::constant(2026, 1, 1),
            Date::constant(2027, 1, 1),
        )
        .unwrap();
        assert_eq!(series.len(), 12);

        let march = &series[2];
        assert_eq!(march.month, Date::constant(2026, 3, 1));
        assert_eq!(march.charged, Decimal::from_str("120.00").unwrap());
        assert_eq!(march.charge_count, 1);
        assert_eq!(march.levelled, Decimal::from_str("10").unwrap());

        let april = &series[3];
        assert_eq!(april.charged, Decimal::ZERO, "nothing falls due in April");
        assert_eq!(april.levelled, Decimal::from_str("10").unwrap());

        // Before the first charge there is neither: spreading the cost
        // backwards would invent months it was never paid for.
        let january = &series[0];
        assert_eq!(january.charged, Decimal::ZERO);
        assert_eq!(january.levelled, Decimal::ZERO);

        // Over a full year the two readings meet.
        let charged: Decimal = series.iter().map(|m| m.charged).sum();
        let levelled: Decimal = series.iter().map(|m| m.levelled).sum();
        assert_eq!(charged, Decimal::from_str("120.00").unwrap());
        assert_eq!(
            levelled,
            Decimal::from_str("100").unwrap(),
            "ten months of it"
        );
    }

    #[test]
    fn months_with_nothing_in_them_are_present_with_zeros() {
        let subs = [sub(
            "Netflix",
            money("10.00", "USD"),
            cycle(3, CycleUnit::Month),
        )];
        let series = monthly_series(
            &subs,
            &histories_of(&subs),
            Date::constant(2026, 1, 1),
            Date::constant(2026, 5, 1),
        )
        .unwrap();
        assert_eq!(series.len(), 4, "a quiet month is still a month");
        assert_eq!(
            series.iter().map(|m| m.charge_count).collect::<Vec<_>>(),
            [1, 0, 0, 1]
        );
    }

    #[test]
    fn currencies_stay_apart_and_archived_subscriptions_stay_out() {
        let mut subs = vec![
            sub("a", money("10.00", "USD"), cycle(1, CycleUnit::Month)),
            sub("b", money("70.00", "CNY"), cycle(1, CycleUnit::Month)),
            sub("c", money("99.00", "USD"), cycle(1, CycleUnit::Month)),
        ];
        subs[2].status = SubscriptionStatus::Archived;

        let series = monthly_series(
            &subs,
            &histories_of(&subs),
            Date::constant(2026, 1, 1),
            Date::constant(2026, 2, 1),
        )
        .unwrap();
        assert_eq!(series.len(), 2, "one month, two currencies, never mixed");
        assert_eq!(series[0].currency, "CNY");
        assert_eq!(series[0].charged, Decimal::from_str("70.00").unwrap());
        assert_eq!(series[1].currency, "USD");
        assert_eq!(
            series[1].charged,
            Decimal::from_str("10.00").unwrap(),
            "the archived one is left out"
        );
    }

    /// A rise has to move both readings, each from the day it took effect.
    #[test]
    fn a_rise_moves_both_readings_from_the_month_it_lands() {
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
        let subs = [s.clone()];
        let histories = HashMap::from([(s.id, history)]);

        let series = monthly_series(
            &subs,
            &histories,
            Date::constant(2026, 1, 1),
            Date::constant(2026, 5, 1),
        )
        .unwrap();
        assert_eq!(
            series.iter().map(|m| m.charged).collect::<Vec<_>>(),
            ["10.00", "10.00", "15.00", "15.00"].map(|s| Decimal::from_str(s).unwrap())
        );
        assert_eq!(
            series.iter().map(|m| m.levelled).collect::<Vec<_>>(),
            ["10", "10", "15", "15"].map(|s| Decimal::from_str(s).unwrap())
        );
    }

    #[test]
    fn shares_are_largest_first_and_keep_the_uncategorized_visible() {
        let filed = Uuid::now_v7();
        let mut subs = vec![
            sub("small", money("5.00", "USD"), cycle(1, CycleUnit::Month)),
            sub("big", money("120.00", "USD"), cycle(1, CycleUnit::Year)),
            sub("loose", money("30.00", "USD"), cycle(1, CycleUnit::Month)),
            sub("gone", money("99.00", "USD"), cycle(1, CycleUnit::Month)),
        ];
        subs[0].category_id = Some(filed);
        subs[1].category_id = Some(filed);
        subs[3].status = SubscriptionStatus::Archived;

        let shares = category_shares(&subs, Date::constant(2026, 6, 1));
        assert_eq!(shares.len(), 2);
        // "loose" at 30 a month beats the filed pair at 5 + 10.
        assert_eq!(shares[0].category_id, None);
        assert_eq!(shares[0].monthly, Decimal::from_str("30.00").unwrap());
        assert_eq!(shares[1].category_id, Some(filed));
        assert_eq!(shares[1].monthly, Decimal::from_str("15.00").unwrap());
        assert_eq!(shares[1].subscription_count, 2);
    }

    /// A share is a question about proportion, so a yearly plan must not
    /// swallow the chart in the month it happens to fall.
    #[test]
    fn a_share_levels_a_yearly_plan_rather_than_spiking_it() {
        let subs = [sub(
            "Adobe",
            money("120.00", "USD"),
            cycle(1, CycleUnit::Year),
        )];
        let shares = category_shares(&subs, Date::constant(2026, 6, 1));
        assert_eq!(shares[0].monthly, Decimal::from_str("10").unwrap());
    }

    #[test]
    fn a_subscription_that_has_not_started_is_not_a_share_yet() {
        let mut s = sub("Grok", money("700", "INR"), cycle(1, CycleUnit::Month));
        s.first_billing_date = Date::constant(2026, 9, 18);
        assert!(category_shares(&[s], Date::constant(2026, 9, 3)).is_empty());
    }

    #[test]
    fn window_totals_price_each_charge_and_keep_currencies_apart() {
        let usd = sub("a", money("10.00", "USD"), cycle(1, CycleUnit::Month));
        let cny = sub("b", money("25.00", "CNY"), cycle(1, CycleUnit::Month));
        let subs = [usd.clone(), cny];
        let mut histories = histories_of(&subs);
        histories.get_mut(&usd.id).unwrap().push(Price {
            id: Uuid::now_v7(),
            subscription_id: usd.id,
            effective_from: Date::constant(2026, 3, 1),
            amount: money("15.00", "USD"),
            created_at: usd.created_at,
            updated_at: usd.updated_at,
        });

        // January through April: USD is 10 + 10 + 15 + 15, CNY is 4 × 25.
        let totals = window_totals(
            &subs,
            &histories,
            Date::constant(2026, 1, 1),
            Date::constant(2026, 5, 1),
        )
        .unwrap();
        assert_eq!(totals.len(), 2);
        assert_eq!(totals[0].currency, "CNY");
        assert_eq!(totals[0].total, Decimal::from_str("100.00").unwrap());
        assert_eq!(totals[1].currency, "USD");
        assert_eq!(totals[1].total, Decimal::from_str("50.00").unwrap());
        assert_eq!(totals[1].charge_count, 4);
    }

    /// The month series and the window total are two views of the same
    /// charges, so they must never disagree about the sum.
    #[test]
    fn a_window_total_matches_the_months_it_spans() {
        let subs = [
            sub("a", money("10.00", "USD"), cycle(1, CycleUnit::Month)),
            sub("b", money("120.00", "USD"), cycle(1, CycleUnit::Year)),
        ];
        let histories = histories_of(&subs);
        let (from, to) = (Date::constant(2026, 1, 1), Date::constant(2027, 1, 1));

        let series = monthly_series(&subs, &histories, from, to).unwrap();
        let totals = window_totals(&subs, &histories, from, to).unwrap();
        assert_eq!(
            series.iter().map(|m| m.charged).sum::<Decimal>(),
            totals[0].total
        );
        assert_eq!(
            series.iter().map(|m| m.charge_count).sum::<u32>(),
            totals[0].charge_count
        );
    }

    #[test]
    fn the_earliest_charge_ignores_archived_subscriptions() {
        let mut old = sub("old", money("1.00", "USD"), cycle(1, CycleUnit::Month));
        old.first_billing_date = Date::constant(2020, 1, 1);
        old.status = SubscriptionStatus::Archived;
        let mut newer = sub("new", money("1.00", "USD"), cycle(1, CycleUnit::Month));
        newer.first_billing_date = Date::constant(2026, 5, 5);

        assert_eq!(
            earliest_charge(&[old, newer]),
            Some(Date::constant(2026, 5, 5))
        );
        assert_eq!(earliest_charge(&[]), None);
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

    // -- converting into a primary currency --

    /// One EUR bought 8.25 CNY and 1.10 USD from 2026-01-01, with nothing
    /// recorded before that day.
    fn rates() -> RateHistories {
        let mut rates = RateHistories::new();
        for (currency, rate) in [("CNY", "8.25"), ("USD", "1.10")] {
            rates.insert(
                currency.to_owned(),
                vec![
                    crate::model::ExchangeRate::new(
                        currency,
                        Date::constant(2026, 1, 1),
                        Decimal::from_str(rate).unwrap(),
                        false,
                    )
                    .unwrap(),
                ],
            );
        }
        rates
    }

    const RATE_DAY: Date = Date::constant(2026, 6, 1);

    #[test]
    fn currencies_are_added_together_once_converted() {
        // 11 USD and 82.50 CNY are both 10 EUR a month, so the total is 20.
        let subs = [
            sub("A", money("11", "USD"), cycle(1, CycleUnit::Month)),
            sub("B", money("82.50", "CNY"), cycle(1, CycleUnit::Month)),
        ];
        let total = summarize_in(&subs, &rates(), "EUR", RATE_DAY).unwrap();

        assert_eq!(total.currency, "EUR");
        assert_eq!(total.subscription_count, 2);
        assert_eq!(total.monthly, Decimal::from_str("20").unwrap());
        assert!(total.unconverted.is_empty());
    }

    #[test]
    fn a_currency_with_no_rate_is_reported_rather_than_dropped() {
        let subs = [
            sub("A", money("11", "USD"), cycle(1, CycleUnit::Month)),
            sub("B", money("1000", "JPY"), cycle(1, CycleUnit::Month)),
        ];
        let total = summarize_in(&subs, &rates(), "EUR", RATE_DAY).unwrap();

        // The converted figure covers only what it can, and says so.
        assert_eq!(total.subscription_count, 1);
        assert_eq!(total.monthly, Decimal::from_str("10").unwrap());
        assert_eq!(total.unconverted.len(), 1);
        assert_eq!(total.unconverted[0].currency, "JPY");
        assert_eq!(total.unconverted[0].subscription_count, 1);
        assert_eq!(
            total.unconverted[0].monthly,
            Decimal::from_str("1000").unwrap()
        );
    }

    #[test]
    fn a_database_with_no_rates_still_totals_a_single_currency() {
        // The common case for somebody who never leaves their own currency:
        // nothing to fetch, and the total must still be right.
        let subs = [
            sub("A", money("10", "CNY"), cycle(1, CycleUnit::Month)),
            sub("B", money("20", "CNY"), cycle(1, CycleUnit::Month)),
        ];
        let total = summarize_in(&subs, &RateHistories::new(), "CNY", RATE_DAY).unwrap();

        assert_eq!(total.monthly, Decimal::from_str("30").unwrap());
        assert!(total.unconverted.is_empty());
    }

    #[test]
    fn archived_subscriptions_stay_out_of_the_converted_total() {
        let mut archived = sub("Old", money("11", "USD"), cycle(1, CycleUnit::Month));
        archived.status = SubscriptionStatus::Archived;
        let subs = [
            sub("A", money("11", "USD"), cycle(1, CycleUnit::Month)),
            archived,
        ];
        let total = summarize_in(&subs, &rates(), "EUR", RATE_DAY).unwrap();

        assert_eq!(total.subscription_count, 1);
        assert_eq!(total.monthly, Decimal::from_str("10").unwrap());
    }

    #[test]
    fn a_subscription_is_totalled_at_the_rate_of_each_charge() {
        // The rate moves between the two charges, so a total built from
        // today's rate alone would be wrong by the difference.
        let mut rates = RateHistories::new();
        rates.insert(
            "USD".to_owned(),
            vec![
                crate::model::ExchangeRate::new(
                    "USD",
                    Date::constant(2026, 1, 1),
                    Decimal::from_str("1.00").unwrap(),
                    false,
                )
                .unwrap(),
                crate::model::ExchangeRate::new(
                    "USD",
                    Date::constant(2026, 2, 1),
                    Decimal::from_str("2.00").unwrap(),
                    false,
                )
                .unwrap(),
            ],
        );
        let s = sub("A", money("10", "USD"), cycle(1, CycleUnit::Month));
        let history = [Price::new(
            s.id,
            money("10", "USD"),
            Date::constant(2026, 1, 1),
        )];

        // January at 1.00 is 10 EUR; February at 2.00 is 5 EUR.
        let total = subscription_total_in(
            &s,
            &history,
            &rates,
            "EUR",
            Date::constant(2026, 3, 1),
            RateBasis::OwnDay,
        )
        .unwrap();
        assert_eq!(total.charge_count, 2);
        assert_eq!(total.converted_charge_count, 2);
        assert_eq!(total.total, Decimal::from_str("15").unwrap());
    }

    #[test]
    fn charges_older_than_the_rate_history_are_counted_but_not_summed() {
        let mut rates = RateHistories::new();
        rates.insert(
            "USD".to_owned(),
            vec![
                crate::model::ExchangeRate::new(
                    "USD",
                    Date::constant(2026, 2, 1),
                    Decimal::from_str("1.00").unwrap(),
                    false,
                )
                .unwrap(),
            ],
        );
        let s = sub("A", money("10", "USD"), cycle(1, CycleUnit::Month));
        let history = [Price::new(
            s.id,
            money("10", "USD"),
            Date::constant(2026, 1, 1),
        )];

        let total = subscription_total_in(
            &s,
            &history,
            &rates,
            "EUR",
            Date::constant(2026, 3, 1),
            RateBasis::OwnDay,
        )
        .unwrap();
        // Two charges fell due; only February's could be converted.
        assert_eq!(total.charge_count, 2);
        assert_eq!(total.converted_charge_count, 1);
        assert_eq!(total.total, Decimal::from_str("10").unwrap());
        assert_eq!(total.first_charge, Some(Date::constant(2026, 1, 1)));
    }

    // -- what a total was built from --

    #[test]
    fn a_total_names_the_rate_each_currency_went_in_at() {
        let subs = [
            sub("A", money("11", "USD"), cycle(1, CycleUnit::Month)),
            sub("B", money("82.50", "CNY"), cycle(1, CycleUnit::Month)),
        ];
        let total = summarize_in(&subs, &rates(), "EUR", RATE_DAY).unwrap();

        // One entry per currency, by code, carrying the pair a person
        // thinks in - not the rate against the base it is stored against.
        let named: Vec<_> = total
            .applied
            .iter()
            .map(|a| (a.currency.as_str(), a.rate.map(|r| r.to_string())))
            .collect();
        assert_eq!(
            named,
            vec![
                ("CNY", Some("0.1212121212121212121212121212".to_owned())),
                ("USD", Some("0.9090909090909090909090909091".to_owned())),
            ]
        );

        // And the amount before conversion, which is what a footnote
        // naming "including US$11.00 at 0.909…" has to print.
        assert_eq!(total.applied[1].monthly, Decimal::from_str("11").unwrap());
    }

    #[test]
    fn the_primary_currency_is_applied_with_no_rate_to_name() {
        // It was not converted, so there is no rate. Printing 1.0000 would
        // say a rate had been looked up when none was.
        let subs = [sub("A", money("10", "EUR"), cycle(1, CycleUnit::Month))];
        let total = summarize_in(&subs, &rates(), "EUR", RATE_DAY).unwrap();

        assert_eq!(total.applied.len(), 1);
        assert_eq!(total.applied[0].currency, "EUR");
        assert_eq!(total.applied[0].rate, None);
    }

    #[test]
    fn a_currency_that_would_not_convert_is_not_among_the_applied() {
        let subs = [
            sub("A", money("11", "USD"), cycle(1, CycleUnit::Month)),
            sub("B", money("1000", "JPY"), cycle(1, CycleUnit::Month)),
        ];
        let total = summarize_in(&subs, &rates(), "EUR", RATE_DAY).unwrap();

        assert_eq!(total.applied.len(), 1);
        assert_eq!(total.applied[0].currency, "USD");
        assert_eq!(total.unconverted.len(), 1);
        assert_eq!(total.unconverted[0].currency, "JPY");
    }

    #[test]
    fn what_was_applied_adds_up_to_the_total_it_came_from() {
        // The property that makes the footnote worth printing: a reader
        // adding up the parts must land on the figure above them.
        let subs = [
            sub("A", money("11", "USD"), cycle(1, CycleUnit::Month)),
            sub("B", money("82.50", "CNY"), cycle(1, CycleUnit::Month)),
            sub("C", money("5", "EUR"), cycle(1, CycleUnit::Month)),
        ];
        let total = summarize_in(&subs, &rates(), "EUR", RATE_DAY).unwrap();

        let rebuilt: Decimal = total
            .applied
            .iter()
            .map(|a| a.rate.map_or(a.monthly, |rate| a.monthly * rate))
            .sum();
        // Not exactly equal: rebuilding multiplies each part by a rate that
        // was itself a division, so it can differ in the last places. What
        // must hold is that it rounds to the same money.
        assert!(
            (rebuilt - total.monthly).abs() < Decimal::from_str("0.0000001").unwrap(),
            "parts summed to {rebuilt}, total was {}",
            total.monthly
        );
    }

    #[test]
    fn pricing_history_at_one_day_drifts_where_pricing_it_per_charge_does_not() {
        // The switch the design offers, and the reason it defaults off:
        // OwnDay is what the money cost, OneDay is what it would cost now.
        let mut rates = RateHistories::new();
        rates.insert(
            "USD".to_owned(),
            vec![
                crate::model::ExchangeRate::new(
                    "USD",
                    Date::constant(2026, 1, 1),
                    Decimal::from_str("1.00").unwrap(),
                    false,
                )
                .unwrap(),
                crate::model::ExchangeRate::new(
                    "USD",
                    Date::constant(2026, 2, 1),
                    Decimal::from_str("2.00").unwrap(),
                    false,
                )
                .unwrap(),
            ],
        );
        let s = sub("A", money("10", "USD"), cycle(1, CycleUnit::Month));
        let history = [Price::new(
            s.id,
            money("10", "USD"),
            Date::constant(2026, 1, 1),
        )];
        let until = Date::constant(2026, 3, 1);

        // January at 1.00 is 10, February at 2.00 is 5: fifteen.
        let own =
            subscription_total_in(&s, &history, &rates, "EUR", until, RateBasis::OwnDay).unwrap();
        assert_eq!(own.total, Decimal::from_str("15").unwrap());

        // Both at the rate in force on 1 March, which is February's 2.00:
        // ten of them, so five each.
        let one =
            subscription_total_in(&s, &history, &rates, "EUR", until, RateBasis::OneDay).unwrap();
        assert_eq!(one.total, Decimal::from_str("10").unwrap());
        assert_eq!(one.converted_charge_count, own.converted_charge_count);
    }

    #[test]
    fn a_charge_before_the_history_converts_under_one_day_that_would_not_under_its_own() {
        // Worth knowing rather than surprising: switching the basis changes
        // which charges can be converted at all, because a day the history
        // does not reach is no longer the day being asked about.
        let mut rates = RateHistories::new();
        rates.insert(
            "USD".to_owned(),
            vec![
                crate::model::ExchangeRate::new(
                    "USD",
                    Date::constant(2026, 2, 1),
                    Decimal::from_str("1.00").unwrap(),
                    false,
                )
                .unwrap(),
            ],
        );
        let s = sub("A", money("10", "USD"), cycle(1, CycleUnit::Month));
        let history = [Price::new(
            s.id,
            money("10", "USD"),
            Date::constant(2026, 1, 1),
        )];
        let until = Date::constant(2026, 3, 1);

        let own =
            subscription_total_in(&s, &history, &rates, "EUR", until, RateBasis::OwnDay).unwrap();
        assert_eq!(own.converted_charge_count, 1, "January has no rate");

        let one =
            subscription_total_in(&s, &history, &rates, "EUR", until, RateBasis::OneDay).unwrap();
        assert_eq!(one.converted_charge_count, 2, "both use March's rate");
    }
}
