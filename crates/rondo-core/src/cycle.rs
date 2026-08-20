//! Billing occurrence math, anchored to the first billing date.
//!
//! Every occurrence is computed as `first + k * cycle` from the original
//! anchor date, never from the previously computed date. Iterating from the
//! last result would drift on short months (Jan 31 -> Feb 28 -> Mar 28),
//! while anchoring keeps the schedule on the intended day (Jan 31 -> Feb 28
//! -> Mar 31).

use jiff::civil::Date;
use jiff::{Span, ToSpan};

use crate::error::{Error, Result};
use crate::model::{BillingCycle, CycleUnit};

/// Upper bound on the occurrence index.
///
/// With `MAX_COUNT`-day cycles this still covers far more than a human
/// lifetime, and it keeps month spans well inside jiff's calendar limits.
const MAX_OCCURRENCE: i64 = 20_000;

/// Returns the date of occurrence `k` (0-based) of a billing schedule.
///
/// Occurrence 0 is `first` itself. Month and year steps clamp to the last
/// day of a short month (Jan 31 + 1 month = Feb 28/29), which is jiff's
/// default behavior for civil-date spans.
///
/// Fails with [`Error::DateOutOfRange`] when `k` is negative, above the
/// supported bound, or the resulting date leaves the supported calendar.
pub fn occurrence(first: Date, cycle: BillingCycle, k: i64) -> Result<Date> {
    if !(0..=MAX_OCCURRENCE).contains(&k) {
        return Err(Error::DateOutOfRange(format!(
            "occurrence index must be 0..={MAX_OCCURRENCE}, got {k}"
        )));
    }
    let steps = k * i64::from(cycle.count());
    let span: Span = match cycle.unit() {
        CycleUnit::Day => steps.days(),
        CycleUnit::Week => steps.weeks(),
        CycleUnit::Month => steps.months(),
        CycleUnit::Year => steps.years(),
    };
    first
        .checked_add(span)
        .map_err(|e| Error::DateOutOfRange(format!("{first} + {steps} {:?}s: {e}", cycle.unit())))
}

/// Returns the earliest occurrence on or after `date`.
///
/// Returns `first` itself when `date` is not after it. Fails with
/// [`Error::DateOutOfRange`] if no occurrence within the supported bound
/// reaches `date`.
pub fn next_billing_date(first: Date, cycle: BillingCycle, date: Date) -> Result<Date> {
    if first >= date {
        return Ok(first);
    }
    // Estimate a lower bound for k from the calendar distance, then walk
    // forward. The estimate deliberately undershoots (month lengths vary),
    // so the loop below only ever has a few steps to take.
    let est = estimate_lower_bound(first, cycle, date);
    let mut k = est;
    loop {
        let occ = occurrence(first, cycle, k)?;
        if occ >= date {
            // The estimate may have overshot on clamped month ends; step back
            // to the earliest occurrence that still reaches `date`.
            while k > 0 && occurrence(first, cycle, k - 1)? >= date {
                k -= 1;
            }
            return occurrence(first, cycle, k);
        }
        k += 1;
    }
}

/// Returns all occurrences in the half-open range `[from, to)`.
///
/// Useful for scheduling reminders over a window. Fails with
/// [`Error::DateOutOfRange`] on the same bounds as [`next_billing_date`].
pub fn occurrences_between(
    first: Date,
    cycle: BillingCycle,
    from: Date,
    to: Date,
) -> Result<Vec<Date>> {
    let mut dates = Vec::new();
    if to <= from {
        return Ok(dates);
    }
    let mut current = next_billing_date(first, cycle, from)?;
    // Re-derive the index so continued iteration stays anchored.
    let mut k = index_of(first, cycle, current)?;
    while current < to {
        dates.push(current);
        k += 1;
        current = occurrence(first, cycle, k)?;
    }
    Ok(dates)
}

/// Conservative lower bound for the occurrence index reaching `date`.
fn estimate_lower_bound(first: Date, cycle: BillingCycle, date: Date) -> i64 {
    let count = i64::from(cycle.count());
    let days = i64::from((date - first).get_days());
    let est = match cycle.unit() {
        CycleUnit::Day => days / count,
        CycleUnit::Week => days / (7 * count),
        // 31 overestimates every month's length, so dividing by it undershoots.
        CycleUnit::Month => days / (31 * count),
        CycleUnit::Year => days / (366 * count),
    };
    est.max(0)
}

/// Returns the occurrence index of `date`, which must be an exact occurrence.
fn index_of(first: Date, cycle: BillingCycle, date: Date) -> Result<i64> {
    let mut k = estimate_lower_bound(first, cycle, date);
    loop {
        let occ = occurrence(first, cycle, k)?;
        if occ == date {
            return Ok(k);
        }
        if occ > date {
            return Err(Error::DateOutOfRange(format!(
                "{date} is not an occurrence of the schedule starting {first}"
            )));
        }
        k += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cycle(count: u32, unit: CycleUnit) -> BillingCycle {
        BillingCycle::new(count, unit).unwrap()
    }

    fn date(y: i16, m: i8, d: i8) -> Date {
        Date::constant(y, m, d)
    }

    #[test]
    fn monthly_occurrences_clamp_to_short_months_without_drifting() {
        let first = date(2024, 1, 31);
        let monthly = cycle(1, CycleUnit::Month);
        // Leap February clamps to 29, but March returns to the anchored 31st.
        assert_eq!(occurrence(first, monthly, 1).unwrap(), date(2024, 2, 29));
        assert_eq!(occurrence(first, monthly, 2).unwrap(), date(2024, 3, 31));
        // A common-year February clamps to 28.
        assert_eq!(occurrence(first, monthly, 13).unwrap(), date(2025, 2, 28));
        assert_eq!(occurrence(first, monthly, 14).unwrap(), date(2025, 3, 31));
    }

    #[test]
    fn yearly_occurrence_clamps_leap_day() {
        let first = date(2024, 2, 29);
        let yearly = cycle(1, CycleUnit::Year);
        assert_eq!(occurrence(first, yearly, 1).unwrap(), date(2025, 2, 28));
        assert_eq!(occurrence(first, yearly, 4).unwrap(), date(2028, 2, 29));
    }

    #[test]
    fn day_and_week_occurrences_are_plain_arithmetic() {
        let first = date(2026, 8, 1);
        assert_eq!(
            occurrence(first, cycle(10, CycleUnit::Day), 3).unwrap(),
            date(2026, 8, 31)
        );
        assert_eq!(
            occurrence(first, cycle(2, CycleUnit::Week), 2).unwrap(),
            date(2026, 8, 29)
        );
    }

    #[test]
    fn next_billing_date_returns_first_when_not_started() {
        let first = date(2026, 9, 1);
        let monthly = cycle(1, CycleUnit::Month);
        assert_eq!(
            next_billing_date(first, monthly, date(2026, 8, 20)).unwrap(),
            first
        );
        // A date equal to an occurrence is returned as-is.
        assert_eq!(
            next_billing_date(first, monthly, date(2026, 9, 1)).unwrap(),
            first
        );
    }

    #[test]
    fn next_billing_date_finds_upcoming_anchored_occurrence() {
        let first = date(2024, 1, 31);
        let monthly = cycle(1, CycleUnit::Month);
        assert_eq!(
            next_billing_date(first, monthly, date(2026, 3, 1)).unwrap(),
            date(2026, 3, 31)
        );
        // The day after the clamped Feb 28 occurrence moves on to March.
        assert_eq!(
            next_billing_date(first, monthly, date(2026, 2, 28).tomorrow().unwrap()).unwrap(),
            date(2026, 3, 31)
        );
        assert_eq!(
            next_billing_date(first, monthly, date(2026, 2, 28)).unwrap(),
            date(2026, 2, 28)
        );
    }

    #[test]
    fn next_billing_date_handles_multi_unit_cycles() {
        let first = date(2025, 11, 30);
        let quarterly = cycle(3, CycleUnit::Month);
        // Quarter ends: Feb (clamped), May, Aug, Nov.
        assert_eq!(
            next_billing_date(first, quarterly, date(2026, 8, 20)).unwrap(),
            date(2026, 8, 30)
        );
        assert_eq!(
            next_billing_date(first, quarterly, date(2026, 1, 15)).unwrap(),
            date(2026, 2, 28)
        );
    }

    #[test]
    fn occurrences_between_covers_half_open_window() {
        let first = date(2026, 1, 31);
        let monthly = cycle(1, CycleUnit::Month);
        let dates =
            occurrences_between(first, monthly, date(2026, 2, 1), date(2026, 5, 1)).unwrap();
        assert_eq!(
            dates,
            vec![date(2026, 2, 28), date(2026, 3, 31), date(2026, 4, 30)]
        );
        // Empty and inverted windows produce no occurrences.
        assert!(
            occurrences_between(first, monthly, date(2026, 5, 1), date(2026, 5, 1))
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn occurrence_rejects_out_of_bound_indexes() {
        let first = date(2026, 1, 1);
        let daily = cycle(1, CycleUnit::Day);
        assert!(occurrence(first, daily, -1).is_err());
        assert!(occurrence(first, daily, MAX_OCCURRENCE + 1).is_err());
    }
}
