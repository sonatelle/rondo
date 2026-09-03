//! The data shapes that cross the boundary.
//!
//! These mirror the core entities with two differences. `Money` and
//! `BillingCycle` are flattened into their parts, because a UniFFI record
//! needs public fields and those types keep theirs private on purpose.
//! Rebuilding a core entity therefore goes back through the validating
//! constructors, so a frontend cannot assemble a subscription the core
//! would have refused.

use jiff::civil::Date;
use rondo_core::model::{
    BillingCycle, Category as CoreCategory, Channel, CycleUnit, Money,
    PaymentMethod as CorePaymentMethod, Price as CorePrice, Subscription as CoreSubscription,
    SubscriptionStatus,
};
use rust_decimal::Decimal;
use uuid::Uuid;

use crate::error::{Result, RondoError};

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

#[uniffi::remote(Enum)]
pub enum Channel {
    AppStore,
    GooglePlay,
    Web,
    Other,
}

/// A recurring subscription, as seen from a frontend.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Subscription {
    pub id: Uuid,
    pub name: String,
    pub notes: Option<String>,
    pub template_id: Option<String>,
    /// Price charged once per cycle, exact, as of the day this was asked
    /// for. A subscription whose price rose has more than one; the whole
    /// history is `price_history`.
    pub amount: Decimal,
    /// Three-letter currency code the amount is denominated in.
    pub currency: String,
    pub cycle_count: u32,
    pub cycle_unit: CycleUnit,
    pub first_billing_date: Date,
    pub reminder_lead_days: u16,
    pub category_id: Option<Uuid>,
    /// Where it was bought; `None` when nobody has said.
    pub channel: Option<Channel>,
    /// The account it is billed to, as the person writes it.
    pub account: Option<String>,
    pub payment_method_id: Option<Uuid>,
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
            amount: sub.price.amount(),
            currency: sub.price.currency().to_owned(),
            cycle_count: sub.cycle.count(),
            cycle_unit: sub.cycle.unit(),
            first_billing_date: sub.first_billing_date,
            reminder_lead_days: sub.reminder_lead_days,
            category_id: sub.category_id,
            channel: sub.channel,
            account: sub.account,
            payment_method_id: sub.payment_method_id,
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
            price: Money::new(sub.amount, &sub.currency)?,
            cycle: BillingCycle::new(sub.cycle_count, sub.cycle_unit)?,
            first_billing_date: sub.first_billing_date,
            reminder_lead_days: sub.reminder_lead_days,
            category_id: sub.category_id,
            channel: sub.channel,
            account: sub.account,
            payment_method_id: sub.payment_method_id,
            status: sub.status,
            created_at: sub.created_at,
            updated_at: sub.updated_at,
        })
    }
}

/// One price and the day it took effect, as seen from a frontend.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Price {
    pub id: Uuid,
    pub subscription_id: Uuid,
    /// The day this price took effect. It applies to charges on or after
    /// it and before the next entry's day.
    pub effective_from: Date,
    pub amount: Decimal,
    pub currency: String,
    pub created_at: jiff::Timestamp,
    pub updated_at: jiff::Timestamp,
}

impl From<CorePrice> for Price {
    fn from(price: CorePrice) -> Self {
        Self {
            id: price.id,
            subscription_id: price.subscription_id,
            effective_from: price.effective_from,
            amount: price.amount.amount(),
            currency: price.amount.currency().to_owned(),
            created_at: price.created_at,
            updated_at: price.updated_at,
        }
    }
}

impl TryFrom<Price> for CorePrice {
    type Error = RondoError;

    fn try_from(price: Price) -> Result<Self> {
        Ok(Self {
            id: price.id,
            subscription_id: price.subscription_id,
            effective_from: price.effective_from,
            amount: Money::new(price.amount, &price.currency)?,
            created_at: price.created_at,
            updated_at: price.updated_at,
        })
    }
}

/// A way of paying, as seen from a frontend.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct PaymentMethod {
    pub id: Uuid,
    pub name: String,
    pub sort_order: i32,
    pub created_at: jiff::Timestamp,
    pub updated_at: jiff::Timestamp,
}

impl From<CorePaymentMethod> for PaymentMethod {
    fn from(method: CorePaymentMethod) -> Self {
        Self {
            id: method.id,
            name: method.name,
            sort_order: method.sort_order,
            created_at: method.created_at,
            updated_at: method.updated_at,
        }
    }
}

impl From<PaymentMethod> for CorePaymentMethod {
    fn from(method: PaymentMethod) -> Self {
        Self {
            id: method.id,
            name: method.name,
            sort_order: method.sort_order,
            created_at: method.created_at,
            updated_at: method.updated_at,
        }
    }
}

/// What one subscription has cost, as seen from a frontend.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SubscriptionTotal {
    pub subscription_id: Uuid,
    pub currency: String,
    /// Every charge summed at the price it was charged at, exact.
    pub total: Decimal,
    pub charge_count: u32,
    pub first_charge: Option<Date>,
    pub last_charge: Option<Date>,
}

impl From<rondo_core::summary::SubscriptionTotal> for SubscriptionTotal {
    fn from(total: rondo_core::summary::SubscriptionTotal) -> Self {
        Self {
            subscription_id: total.subscription_id,
            currency: total.currency,
            total: total.total,
            charge_count: total.charge_count,
            first_charge: total.first_charge,
            last_charge: total.last_charge,
        }
    }
}

/// One month's spending in one currency, read both ways.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MonthlySpending {
    /// First day of the month this covers.
    pub month: Date,
    pub currency: String,
    /// What actually falls due this month.
    pub charged: Decimal,
    /// The same cost spread evenly, so a yearly plan is a twelfth a month.
    pub levelled: Decimal,
    pub charge_count: u32,
}

impl From<rondo_core::summary::MonthlySpending> for MonthlySpending {
    fn from(month: rondo_core::summary::MonthlySpending) -> Self {
        Self {
            month: month.month,
            currency: month.currency,
            charged: month.charged,
            levelled: month.levelled,
            charge_count: month.charge_count,
        }
    }
}

/// What one category costs a month, in one currency.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CategoryShare {
    /// `None` groups the subscriptions filed under nothing, which are kept
    /// so a share adds up to the whole.
    pub category_id: Option<Uuid>,
    pub currency: String,
    pub monthly: Decimal,
    pub subscription_count: u32,
}

impl From<rondo_core::summary::CategoryShare> for CategoryShare {
    fn from(share: rondo_core::summary::CategoryShare) -> Self {
        Self {
            category_id: share.category_id,
            currency: share.currency,
            monthly: share.monthly,
            subscription_count: share.subscription_count,
        }
    }
}

/// What was spent over some window, in one currency.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct WindowTotal {
    pub currency: String,
    pub total: Decimal,
    pub charge_count: u32,
}

impl From<rondo_core::summary::WindowTotal> for WindowTotal {
    fn from(total: rondo_core::summary::WindowTotal) -> Self {
        Self {
            currency: total.currency,
            total: total.total,
            charge_count: total.charge_count,
        }
    }
}

/// A grouping for subscriptions, as seen from a frontend.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Category {
    pub id: Uuid,
    pub name: String,
    pub sort_order: i32,
    /// Semantic key of the icon, such as `"video"`, for the frontend to map
    /// to a symbol of its own. `None` leaves the choice to the frontend.
    pub icon_key: Option<String>,
    /// Semantic key of the colour, likewise mapped by the frontend rather
    /// than carried as a hex value that could only suit one theme.
    pub color_key: Option<String>,
}

impl From<CoreCategory> for Category {
    fn from(category: CoreCategory) -> Self {
        Self {
            id: category.id,
            name: category.name,
            sort_order: category.sort_order,
            icon_key: category.icon_key,
            color_key: category.color_key,
        }
    }
}

impl From<Category> for CoreCategory {
    fn from(category: Category) -> Self {
        Self {
            id: category.id,
            name: category.name,
            sort_order: category.sort_order,
            icon_key: category.icon_key,
            color_key: category.color_key,
        }
    }
}

/// A bundled service the person can start from instead of typing details.
///
/// The aliases a service is searchable under deliberately do not cross:
/// they are the input to matching, not something to show, and handing them
/// over would invite a frontend to match on them itself and drift from
/// what every other frontend finds.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ServiceTemplate {
    pub id: String,
    pub name: String,
    /// Accent color as `#RRGGBB`.
    pub color: String,
    /// Semantic key of the category a subscription starts in, such as
    /// `"video"`. Each frontend maps it to its own icon and colour.
    pub default_category: String,
    pub url: Option<String>,
}

impl From<&rondo_core::ServiceTemplate> for ServiceTemplate {
    fn from(template: &rondo_core::ServiceTemplate) -> Self {
        Self {
            id: template.id.clone(),
            name: template.name.clone(),
            color: template.color.clone(),
            default_category: template.default_category.clone(),
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

/// Bundled services matching what someone has typed, best match first.
///
/// An empty query returns the whole catalogue, so a picker can call this
/// for every keystroke and for the state before the first one.
#[uniffi::export]
pub fn search_service_templates(query: String) -> Vec<ServiceTemplate> {
    rondo_core::templates::search_service_templates(&query)
        .into_iter()
        .map(ServiceTemplate::from)
        .collect()
}

/// The template id standing for "not on this list".
///
/// Exposed rather than spelled out in each frontend so that "the person
/// chose custom" and "the person has not chosen" stay two different
/// things, and stay the same two things everywhere.
#[uniffi::export]
pub fn custom_template_id() -> String {
    rondo_core::templates::CUSTOM_TEMPLATE_ID.to_string()
}

/// Normalized spending for one currency.
///
/// The totals keep full precision; rounding is the frontend's decision,
/// made once when the number is shown.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SpendingSummary {
    pub currency: String,
    pub subscription_count: u32,
    pub monthly: Decimal,
    pub yearly: Decimal,
}

impl From<rondo_core::summary::SpendingSummary> for SpendingSummary {
    fn from(summary: rondo_core::summary::SpendingSummary) -> Self {
        Self {
            currency: summary.currency,
            subscription_count: summary.subscription_count,
            monthly: summary.monthly,
            yearly: summary.yearly,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
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
        assert_eq!(crossed.amount.to_string(), "15.90");
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
