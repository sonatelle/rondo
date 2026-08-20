//! Domain entities: subscriptions, categories, money, and billing cycles.

use jiff::Timestamp;
use jiff::civil::Date;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::{Error, Result};

/// Unit of a billing cycle.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CycleUnit {
    Day,
    Week,
    Month,
    Year,
}

/// How often a subscription renews: every `count` `unit`s.
///
/// Constructed through [`BillingCycle::new`] so the count invariant
/// (1..=`MAX_COUNT`) always holds; the bound also keeps downstream span
/// arithmetic far away from calendar limits.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "RawBillingCycle", into = "RawBillingCycle")]
pub struct BillingCycle {
    count: u32,
    unit: CycleUnit,
}

/// Serde mirror of [`BillingCycle`] used to re-validate on deserialization.
#[derive(Serialize, Deserialize)]
struct RawBillingCycle {
    count: u32,
    unit: CycleUnit,
}

impl TryFrom<RawBillingCycle> for BillingCycle {
    type Error = Error;

    fn try_from(raw: RawBillingCycle) -> Result<Self> {
        Self::new(raw.count, raw.unit)
    }
}

impl From<BillingCycle> for RawBillingCycle {
    fn from(cycle: BillingCycle) -> Self {
        Self {
            count: cycle.count,
            unit: cycle.unit,
        }
    }
}

impl BillingCycle {
    /// Largest accepted cycle count; a longer cycle is almost certainly input error.
    pub const MAX_COUNT: u32 = 100;

    /// Creates a cycle of every `count` `unit`s.
    ///
    /// Fails with [`Error::InvalidCycle`] when `count` is zero or above
    /// [`Self::MAX_COUNT`].
    pub fn new(count: u32, unit: CycleUnit) -> Result<Self> {
        if count == 0 || count > Self::MAX_COUNT {
            return Err(Error::InvalidCycle(format!(
                "count must be 1..={}, got {count}",
                Self::MAX_COUNT
            )));
        }
        Ok(Self { count, unit })
    }

    /// Number of units between renewals (always 1..=[`Self::MAX_COUNT`]).
    pub fn count(&self) -> u32 {
        self.count
    }

    /// Unit the cycle is counted in.
    pub fn unit(&self) -> CycleUnit {
        self.unit
    }
}

/// An amount of money in a single currency.
///
/// Amounts are exact decimals; rounding happens only at presentation time.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "RawMoney", into = "RawMoney")]
pub struct Money {
    amount: Decimal,
    currency: String,
}

/// Serde mirror of [`Money`] used to re-validate on deserialization.
#[derive(Serialize, Deserialize)]
struct RawMoney {
    amount: Decimal,
    currency: String,
}

impl TryFrom<RawMoney> for Money {
    type Error = Error;

    fn try_from(raw: RawMoney) -> Result<Self> {
        Self::new(raw.amount, &raw.currency)
    }
}

impl From<Money> for RawMoney {
    fn from(money: Money) -> Self {
        Self {
            amount: money.amount,
            currency: money.currency,
        }
    }
}

impl Money {
    /// Creates a money value.
    ///
    /// Fails with [`Error::InvalidMoney`] when the amount is negative or the
    /// currency is not a three-letter uppercase ASCII code (ISO 4217 shape;
    /// the code list itself is not enforced).
    pub fn new(amount: Decimal, currency: &str) -> Result<Self> {
        if amount.is_sign_negative() {
            return Err(Error::InvalidMoney(format!("negative amount {amount}")));
        }
        if currency.len() != 3 || !currency.bytes().all(|b| b.is_ascii_uppercase()) {
            return Err(Error::InvalidMoney(format!(
                "currency must be a three-letter uppercase code, got {currency:?}"
            )));
        }
        Ok(Self {
            amount,
            currency: currency.to_owned(),
        })
    }

    /// Exact decimal amount.
    pub fn amount(&self) -> Decimal {
        self.amount
    }

    /// Three-letter uppercase currency code.
    pub fn currency(&self) -> &str {
        &self.currency
    }
}

/// Whether a subscription is currently billed or kept only as history.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SubscriptionStatus {
    Active,
    Archived,
}

/// A recurring subscription the user pays for.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Subscription {
    /// Stable identity; also the sync identity if devices ever sync.
    pub id: Uuid,
    /// Display name; never empty.
    pub name: String,
    /// Free-form user notes.
    pub notes: Option<String>,
    /// Id of the bundled service template this was created from, if any.
    pub template_id: Option<String>,
    /// Price charged once per billing cycle.
    pub price: Money,
    /// How often the price is charged.
    pub cycle: BillingCycle,
    /// Civil date of the first (or anchor) charge; occurrences derive from it.
    pub first_billing_date: Date,
    /// How many days before a renewal the user wants a reminder.
    pub reminder_lead_days: u16,
    /// Optional category assignment.
    pub category_id: Option<Uuid>,
    /// Active subscriptions bill and count toward summaries; archived ones do not.
    pub status: SubscriptionStatus,
    /// Creation instant (UTC). Kept accurate for future sync.
    pub created_at: Timestamp,
    /// Last modification instant (UTC). Kept accurate for future sync.
    pub updated_at: Timestamp,
}

impl Subscription {
    /// Default reminder lead when the user has not chosen one.
    pub const DEFAULT_REMINDER_LEAD_DAYS: u16 = 3;

    /// Creates an active subscription with a fresh id and current timestamps.
    ///
    /// Fails with [`Error::InvalidSubscription`] when `name` is empty or
    /// whitespace-only.
    pub fn new(
        name: &str,
        price: Money,
        cycle: BillingCycle,
        first_billing_date: Date,
    ) -> Result<Self> {
        let name = name.trim();
        if name.is_empty() {
            return Err(Error::InvalidSubscription("name must not be empty".into()));
        }
        let now = Timestamp::now();
        Ok(Self {
            id: Uuid::new_v4(),
            name: name.to_owned(),
            notes: None,
            template_id: None,
            price,
            cycle,
            first_billing_date,
            reminder_lead_days: Self::DEFAULT_REMINDER_LEAD_DAYS,
            category_id: None,
            status: SubscriptionStatus::Active,
            created_at: now,
            updated_at: now,
        })
    }
}

/// A user-defined grouping for subscriptions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Category {
    /// Stable identity.
    pub id: Uuid,
    /// Display name.
    pub name: String,
    /// Manual ordering position in category lists.
    pub sort_order: i32,
}

impl Category {
    /// Creates a category with a fresh id.
    ///
    /// Fails with [`Error::InvalidSubscription`] when `name` is empty or
    /// whitespace-only.
    pub fn new(name: &str, sort_order: i32) -> Result<Self> {
        let name = name.trim();
        if name.is_empty() {
            return Err(Error::InvalidSubscription(
                "category name must not be empty".into(),
            ));
        }
        Ok(Self {
            id: Uuid::new_v4(),
            name: name.to_owned(),
            sort_order,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn billing_cycle_rejects_zero_and_oversized_counts() {
        assert!(BillingCycle::new(0, CycleUnit::Month).is_err());
        assert!(BillingCycle::new(BillingCycle::MAX_COUNT + 1, CycleUnit::Day).is_err());
        assert!(BillingCycle::new(1, CycleUnit::Month).is_ok());
    }

    #[test]
    fn money_rejects_negative_amounts_and_bad_currencies() {
        let one = Decimal::ONE;
        assert!(Money::new(-one, "USD").is_err());
        assert!(Money::new(one, "usd").is_err());
        assert!(Money::new(one, "US").is_err());
        assert!(Money::new(one, "USDX").is_err());
        assert!(Money::new(one, "USD").is_ok());
    }

    #[test]
    fn subscription_requires_a_name() {
        let price = Money::new(Decimal::ONE, "USD").unwrap();
        let cycle = BillingCycle::new(1, CycleUnit::Month).unwrap();
        let date = Date::constant(2026, 1, 15);
        assert!(Subscription::new("  ", price.clone(), cycle, date).is_err());
        let sub = Subscription::new(" Netflix ", price, cycle, date).unwrap();
        assert_eq!(sub.name, "Netflix");
        assert_eq!(sub.status, SubscriptionStatus::Active);
    }

    #[test]
    fn billing_cycle_deserialization_revalidates() {
        let bad: std::result::Result<BillingCycle, _> =
            serde_json::from_str(r#"{"count":0,"unit":"month"}"#);
        assert!(bad.is_err());
        let good: BillingCycle = serde_json::from_str(r#"{"count":3,"unit":"month"}"#).unwrap();
        assert_eq!(good.count(), 3);
        assert_eq!(good.unit(), CycleUnit::Month);
    }

    #[test]
    fn money_deserialization_revalidates() {
        let bad: std::result::Result<Money, _> =
            serde_json::from_str(r#"{"amount":"1.00","currency":"usd"}"#);
        assert!(bad.is_err());
        let good: Money = serde_json::from_str(r#"{"amount":"15.99","currency":"USD"}"#).unwrap();
        assert_eq!(good.currency(), "USD");
    }
}
