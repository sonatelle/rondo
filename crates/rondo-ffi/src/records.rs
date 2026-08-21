//! The data shapes that cross the boundary.
//!
//! These mirror the core entities with two differences. `Money` and
//! `BillingCycle` are flattened into their parts, because a UniFFI record
//! needs public fields and those types keep theirs private on purpose.
//! Rebuilding a core entity therefore goes back through the validating
//! constructors, so a frontend cannot assemble a subscription the core
//! would have refused.

use rondo_core::model::{
    BillingCycle, Category as CoreCategory, CycleUnit, Money, Subscription as CoreSubscription,
    SubscriptionStatus,
};
use uuid::Uuid;

use crate::error::{Result, RondoError};
use crate::types::{CivilDate, DecimalString};

#[uniffi::remote(Enum)]
pub enum CycleUnit {
    Day,
    Week,
    Month,
    Year,
}

#[uniffi::remote(Enum)]
pub enum SubscriptionStatus {
    Active,
    Archived,
}

/// A recurring subscription, as seen from a frontend.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Subscription {
    pub id: Uuid,
    pub name: String,
    pub notes: Option<String>,
    pub template_id: Option<String>,
    /// Price charged once per cycle, exact.
    pub amount: DecimalString,
    /// Three-letter currency code the amount is denominated in.
    pub currency: String,
    pub cycle_count: u32,
    pub cycle_unit: CycleUnit,
    pub first_billing_date: CivilDate,
    pub reminder_lead_days: u16,
    pub category_id: Option<Uuid>,
    pub status: SubscriptionStatus,
    pub created_at: jiff::Timestamp,
    pub updated_at: jiff::Timestamp,
}

impl From<CoreSubscription> for Subscription {
    fn from(sub: CoreSubscription) -> Self {
        Self {
            id: sub.id,
            name: sub.name,
            notes: sub.notes,
            template_id: sub.template_id,
            amount: DecimalString(sub.price.amount()),
            currency: sub.price.currency().to_owned(),
            cycle_count: sub.cycle.count(),
            cycle_unit: sub.cycle.unit(),
            first_billing_date: CivilDate(sub.first_billing_date),
            reminder_lead_days: sub.reminder_lead_days,
            category_id: sub.category_id,
            status: sub.status,
            created_at: sub.created_at,
            updated_at: sub.updated_at,
        }
    }
}

impl TryFrom<Subscription> for CoreSubscription {
    type Error = RondoError;

    fn try_from(sub: Subscription) -> Result<Self> {
        Ok(Self {
            id: sub.id,
            name: sub.name,
            notes: sub.notes,
            template_id: sub.template_id,
            price: Money::new(sub.amount.0, &sub.currency)?,
            cycle: BillingCycle::new(sub.cycle_count, sub.cycle_unit)?,
            first_billing_date: sub.first_billing_date.0,
            reminder_lead_days: sub.reminder_lead_days,
            category_id: sub.category_id,
            status: sub.status,
            created_at: sub.created_at,
            updated_at: sub.updated_at,
        })
    }
}

/// A grouping for subscriptions, as seen from a frontend.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Category {
    pub id: Uuid,
    pub name: String,
    pub sort_order: i32,
}

impl From<CoreCategory> for Category {
    fn from(category: CoreCategory) -> Self {
        Self {
            id: category.id,
            name: category.name,
            sort_order: category.sort_order,
        }
    }
}

impl From<Category> for CoreCategory {
    fn from(category: Category) -> Self {
        Self {
            id: category.id,
            name: category.name,
            sort_order: category.sort_order,
        }
    }
}

/// A bundled service the person can start from instead of typing details.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ServiceTemplate {
    pub id: String,
    pub name: String,
    /// Accent color as `#RRGGBB`.
    pub color: String,
    pub url: Option<String>,
}

impl From<&rondo_core::ServiceTemplate> for ServiceTemplate {
    fn from(template: &rondo_core::ServiceTemplate) -> Self {
        Self {
            id: template.id.clone(),
            name: template.name.clone(),
            color: template.color.clone(),
            url: template.url.clone(),
        }
    }
}

/// The bundled service catalogue.
///
/// Deliberately not a method on an open database: the picker in a
/// creation form should not need one, and the catalogue is the same for
/// everyone. It is compiled in, so this never fails or touches the disk.
#[uniffi::export]
pub fn service_templates() -> Vec<ServiceTemplate> {
    rondo_core::templates::service_templates()
        .iter()
        .map(ServiceTemplate::from)
        .collect()
}

/// Normalized spending for one currency.
///
/// The totals keep full precision; rounding is the frontend's decision,
/// made once when the number is shown.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SpendingSummary {
    pub currency: String,
    pub subscription_count: u32,
    pub monthly: DecimalString,
    pub yearly: DecimalString,
}

impl From<rondo_core::summary::SpendingSummary> for SpendingSummary {
    fn from(summary: rondo_core::summary::SpendingSummary) -> Self {
        Self {
            currency: summary.currency,
            subscription_count: summary.subscription_count,
            monthly: DecimalString(summary.monthly),
            yearly: DecimalString(summary.yearly),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use jiff::civil::Date;
    use rust_decimal::Decimal;
    use std::str::FromStr;

    fn core_subscription() -> CoreSubscription {
        let mut sub = CoreSubscription::new(
            "Netflix",
            Money::new(Decimal::from_str("15.90").unwrap(), "USD").unwrap(),
            BillingCycle::new(1, CycleUnit::Month).unwrap(),
            Date::constant(2026, 1, 31),
        )
        .unwrap();
        sub.notes = Some("family plan".into());
        sub
    }

    #[test]
    fn a_subscription_survives_the_trip_out_and_back() {
        let original = core_subscription();
        let crossed = Subscription::from(original.clone());
        let returned = CoreSubscription::try_from(crossed).unwrap();
        assert_eq!(returned, original);
    }

    #[test]
    fn the_amount_keeps_its_scale_on_the_way_out() {
        let crossed = Subscription::from(core_subscription());
        // Not 15.9: the trailing zero is part of the price.
        assert_eq!(crossed.amount.0.to_string(), "15.90");
        assert_eq!(crossed.currency, "USD");
    }

    #[test]
    fn a_frontend_cannot_assemble_a_subscription_the_core_would_refuse() {
        let mut crossed = Subscription::from(core_subscription());
        crossed.currency = "dollars".into();
        assert!(matches!(
            CoreSubscription::try_from(crossed.clone()),
            Err(RondoError::InvalidInput { .. })
        ));

        let mut crossed = Subscription::from(core_subscription());
        crossed.cycle_count = 0;
        assert!(matches!(
            CoreSubscription::try_from(crossed),
            Err(RondoError::InvalidInput { .. })
        ));
    }

    #[test]
    fn a_category_survives_the_trip_out_and_back() {
        let original = CoreCategory::new("Streaming", 3).unwrap();
        let returned = CoreCategory::from(Category::from(original.clone()));
        assert_eq!(returned, original);
    }
}
