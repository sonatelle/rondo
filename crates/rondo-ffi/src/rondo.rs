//! The object a frontend holds and calls into.

use std::path::PathBuf;
use std::sync::{Arc, Mutex, MutexGuard};

use rondo_core::Store;
use rondo_core::model::{
    BillingCycle, Category as CoreCategory, Money, Subscription as CoreSubscription,
    SubscriptionStatus,
};
use uuid::Uuid;

use crate::error::{Result, RondoError};
use crate::records::{Category, SpendingSummary, Subscription};
use crate::types::{CivilDate, DecimalString};

/// An open Rondo database.
///
/// UniFFI shares an object as `Arc<Self>` and a frontend may call it from
/// whichever thread it likes, so the store sits behind a mutex. That also
/// matches SQLite: one connection, one operation at a time.
#[derive(uniffi::Object)]
pub struct Rondo {
    store: Mutex<Store>,
}

/// The fields a person fills in to create a subscription.
///
/// Identity and timestamps are deliberately absent: the core assigns them,
/// so a frontend cannot invent an id or backdate a record.
#[derive(Debug, Clone, uniffi::Record)]
pub struct NewSubscription {
    pub name: String,
    pub amount: DecimalString,
    pub currency: String,
    pub cycle_count: u32,
    pub cycle_unit: rondo_core::model::CycleUnit,
    pub first_billing_date: CivilDate,
    pub notes: Option<String>,
    pub template_id: Option<String>,
    pub category_id: Option<Uuid>,
    /// Days of warning before a renewal; the core's default when absent.
    pub reminder_lead_days: Option<u16>,
}

/// A subscription paired with the next date it will be charged.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Renewal {
    pub subscription: Subscription,
    /// The first charge falling on or after the day that was asked about.
    pub date: CivilDate,
}

#[uniffi::export]
impl Rondo {
    /// Opens the database at `path`, creating and migrating it if needed.
    #[uniffi::constructor]
    pub fn open(path: String) -> Result<Arc<Self>> {
        let store = Store::open(&PathBuf::from(path))?;
        Ok(Arc::new(Self {
            store: Mutex::new(store),
        }))
    }

    /// Opens a database that lives only as long as this object.
    ///
    /// Frontends use this for previews and tests, where writing to the
    /// person's real file would be wrong.
    #[uniffi::constructor]
    pub fn open_in_memory() -> Result<Arc<Self>> {
        let store = Store::open_in_memory()?;
        Ok(Arc::new(Self {
            store: Mutex::new(store),
        }))
    }

    /// Lists subscriptions, archived ones included only when asked.
    pub fn subscriptions(&self, include_archived: bool) -> Result<Vec<Subscription>> {
        let filter = (!include_archived).then_some(SubscriptionStatus::Active);
        Ok(self
            .store()?
            .subscriptions(filter)?
            .into_iter()
            .map(Subscription::from)
            .collect())
    }

    /// Loads one subscription, or nothing if that id is unknown.
    pub fn subscription(&self, id: Uuid) -> Result<Option<Subscription>> {
        Ok(self.store()?.subscription(id)?.map(Subscription::from))
    }

    /// Records a new subscription and returns it as stored.
    pub fn add_subscription(&self, draft: NewSubscription) -> Result<Subscription> {
        let mut sub = CoreSubscription::new(
            &draft.name,
            Money::new(draft.amount.0, &draft.currency)?,
            BillingCycle::new(draft.cycle_count, draft.cycle_unit)?,
            draft.first_billing_date.0,
        )?;
        sub.notes = draft.notes;
        sub.template_id = draft.template_id;
        sub.category_id = draft.category_id;
        if let Some(days) = draft.reminder_lead_days {
            sub.reminder_lead_days = days;
        }
        self.store()?.insert_subscription(&sub)?;
        Ok(sub.into())
    }

    /// Saves an edited subscription and returns it with a fresh
    /// `updated_at`, which is the value the frontend should keep.
    pub fn update_subscription(&self, subscription: Subscription) -> Result<Subscription> {
        let sub = CoreSubscription::try_from(subscription)?;
        Ok(self.store()?.update_subscription(&sub)?.into())
    }

    /// Deletes a subscription; reports whether one was there to delete.
    pub fn delete_subscription(&self, id: Uuid) -> Result<bool> {
        Ok(self.store()?.delete_subscription(id)?)
    }

    /// Lists subscriptions with their next charge, soonest first.
    ///
    /// `from` is the day to reckon against - the frontend's own calendar
    /// day, since a billing date is a date on a calendar and only the
    /// frontend knows which one the person is looking at. Subscriptions
    /// renewing on the same day are ordered by name so the list does not
    /// shuffle between refreshes.
    pub fn renewals(&self, from: CivilDate, include_archived: bool) -> Result<Vec<Renewal>> {
        let mut renewals = Vec::new();
        for sub in self.subscriptions(include_archived)? {
            let date = rondo_core::cycle::next_billing_date(
                sub.first_billing_date.0,
                BillingCycle::new(sub.cycle_count, sub.cycle_unit)?,
                from.0,
            )?;
            renewals.push(Renewal {
                subscription: sub,
                date: CivilDate(date),
            });
        }
        renewals.sort_by(|a, b| {
            a.date
                .0
                .cmp(&b.date.0)
                .then_with(|| a.subscription.name.cmp(&b.subscription.name))
        });
        Ok(renewals)
    }

    /// Totals active spending, one entry per currency.
    ///
    /// Currencies are never mixed and archived subscriptions are left out.
    /// The totals carry full precision; rounding is the frontend's call,
    /// made once when the number is shown.
    pub fn spending_summary(&self) -> Result<Vec<SpendingSummary>> {
        let subscriptions = self.store()?.subscriptions(None)?;
        Ok(rondo_core::summary::summarize(&subscriptions)
            .into_iter()
            .map(SpendingSummary::from)
            .collect())
    }

    /// Lists categories in the order the person arranged them.
    pub fn categories(&self) -> Result<Vec<Category>> {
        Ok(self
            .store()?
            .categories()?
            .into_iter()
            .map(Category::from)
            .collect())
    }

    /// Creates a category and returns it with its assigned id.
    pub fn add_category(&self, name: String, sort_order: i32) -> Result<Category> {
        let category = CoreCategory::new(&name, sort_order)?;
        self.store()?.insert_category(&category)?;
        Ok(category.into())
    }

    /// Saves a renamed or reordered category.
    pub fn update_category(&self, category: Category) -> Result<()> {
        Ok(self.store()?.update_category(&category.into())?)
    }

    /// Deletes a category; reports whether one was there to delete.
    ///
    /// Subscriptions filed under it are kept and simply lose the
    /// assignment, so deleting a grouping never deletes what it grouped.
    pub fn delete_category(&self, id: Uuid) -> Result<bool> {
        Ok(self.store()?.delete_category(id)?)
    }

    /// Moves a subscription into or out of the archive.
    ///
    /// Archiving keeps the record and its history but drops it from the
    /// active list and from spending totals.
    pub fn set_archived(&self, id: Uuid, archived: bool) -> Result<Subscription> {
        let store = self.store()?;
        let mut sub = store
            .subscription(id)?
            .ok_or_else(|| RondoError::InvalidInput {
                message: format!("no subscription with id {id}"),
            })?;
        sub.status = if archived {
            SubscriptionStatus::Archived
        } else {
            SubscriptionStatus::Active
        };
        Ok(store.update_subscription(&sub)?.into())
    }
}

impl Rondo {
    /// Borrows the store, turning a poisoned lock into a reportable error.
    ///
    /// Poisoning means an earlier call panicked mid-operation, so the
    /// database may hold a half-finished change. Refusing to continue is
    /// safer than handing out a guard as though nothing happened.
    fn store(&self) -> Result<MutexGuard<'_, Store>> {
        self.store.lock().map_err(|_| RondoError::Storage {
            message: "the database was left in an unknown state by an earlier failure".into(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use jiff::civil::Date;
    use rondo_core::model::CycleUnit;
    use rust_decimal::Decimal;
    use std::str::FromStr;

    fn draft(name: &str) -> NewSubscription {
        NewSubscription {
            name: name.to_owned(),
            amount: DecimalString(Decimal::from_str("15.90").unwrap()),
            currency: "USD".into(),
            cycle_count: 1,
            cycle_unit: CycleUnit::Month,
            first_billing_date: CivilDate(Date::constant(2026, 1, 31)),
            notes: None,
            template_id: None,
            category_id: None,
            reminder_lead_days: None,
        }
    }

    fn open() -> Arc<Rondo> {
        Rondo::open_in_memory().unwrap()
    }

    #[test]
    fn a_subscription_can_be_added_and_read_back() {
        let rondo = open();
        let added = rondo.add_subscription(draft("Netflix")).unwrap();
        assert_eq!(added.name, "Netflix");
        assert_eq!(added.amount.0.to_string(), "15.90");

        let loaded = rondo.subscription(added.id).unwrap().unwrap();
        assert_eq!(loaded, added);
        assert_eq!(rondo.subscriptions(false).unwrap(), vec![added]);
    }

    #[test]
    fn an_unknown_id_reads_as_nothing_rather_than_failing() {
        let rondo = open();
        assert!(rondo.subscription(Uuid::now_v7()).unwrap().is_none());
        assert!(!rondo.delete_subscription(Uuid::now_v7()).unwrap());
    }

    #[test]
    fn a_rejected_draft_never_reaches_the_database() {
        let rondo = open();
        let mut bad = draft("Netflix");
        bad.currency = "dollars".into();
        assert!(matches!(
            rondo.add_subscription(bad),
            Err(RondoError::InvalidInput { .. })
        ));
        assert!(rondo.subscriptions(true).unwrap().is_empty());
    }

    #[test]
    fn editing_returns_the_stored_value_with_a_new_timestamp() {
        let rondo = open();
        let mut sub = rondo.add_subscription(draft("Netflix")).unwrap();
        sub.name = "Netflix Premium".into();
        let saved = rondo.update_subscription(sub.clone()).unwrap();

        assert_eq!(saved.name, "Netflix Premium");
        assert!(saved.updated_at >= sub.updated_at);
        assert_eq!(rondo.subscription(sub.id).unwrap().unwrap(), saved);
    }

    #[test]
    fn archiving_hides_a_subscription_without_deleting_it() {
        let rondo = open();
        let sub = rondo.add_subscription(draft("Netflix")).unwrap();

        rondo.set_archived(sub.id, true).unwrap();
        assert!(rondo.subscriptions(false).unwrap().is_empty());
        assert_eq!(rondo.subscriptions(true).unwrap().len(), 1);

        rondo.set_archived(sub.id, false).unwrap();
        assert_eq!(rondo.subscriptions(false).unwrap().len(), 1);
    }

    #[test]
    fn renewals_come_back_soonest_first() {
        let rondo = open();
        let mut monthly = draft("Monthly");
        monthly.first_billing_date = CivilDate(Date::constant(2026, 8, 5));
        let mut yearly = draft("Yearly");
        yearly.cycle_unit = CycleUnit::Year;
        yearly.first_billing_date = CivilDate(Date::constant(2026, 3, 15));
        rondo.add_subscription(yearly).unwrap();
        rondo.add_subscription(monthly).unwrap();

        let from = CivilDate(Date::constant(2026, 8, 21));
        let renewals = rondo.renewals(from, false).unwrap();
        assert_eq!(
            renewals
                .iter()
                .map(|r| (r.subscription.name.as_str(), r.date.0.to_string()))
                .collect::<Vec<_>>(),
            vec![
                ("Monthly", "2026-09-05".into()),
                ("Yearly", "2027-03-15".into())
            ]
        );
    }

    #[test]
    fn a_renewal_date_stays_anchored_across_a_short_month() {
        let rondo = open();
        // First charged on the 31st, so February clamps but March does not.
        let sub = rondo.add_subscription(draft("Netflix")).unwrap();
        assert_eq!(sub.first_billing_date.0.to_string(), "2026-01-31");

        let february = rondo
            .renewals(CivilDate(Date::constant(2026, 2, 1)), false)
            .unwrap();
        assert_eq!(february[0].date.0.to_string(), "2026-02-28");

        let march = rondo
            .renewals(CivilDate(Date::constant(2026, 3, 1)), false)
            .unwrap();
        assert_eq!(march[0].date.0.to_string(), "2026-03-31");
    }

    #[test]
    fn renewals_on_the_same_day_keep_a_stable_order() {
        let rondo = open();
        for name in ["Zulu", "Alpha"] {
            rondo.add_subscription(draft(name)).unwrap();
        }
        let renewals = rondo
            .renewals(CivilDate(Date::constant(2026, 1, 1)), false)
            .unwrap();
        let names: Vec<&str> = renewals
            .iter()
            .map(|r| r.subscription.name.as_str())
            .collect();
        assert_eq!(names, vec!["Alpha", "Zulu"]);
    }

    #[test]
    fn categories_can_be_created_renamed_and_removed() {
        let rondo = open();
        let mut streaming = rondo.add_category("Streaming".into(), 0).unwrap();
        rondo.add_category("Tools".into(), 1).unwrap();

        streaming.name = "Video".into();
        rondo.update_category(streaming.clone()).unwrap();
        let names: Vec<String> = rondo
            .categories()
            .unwrap()
            .into_iter()
            .map(|c| c.name)
            .collect();
        assert_eq!(names, vec!["Video", "Tools"]);

        assert!(rondo.delete_category(streaming.id).unwrap());
        assert!(!rondo.delete_category(streaming.id).unwrap());
    }

    #[test]
    fn deleting_a_category_keeps_what_it_grouped() {
        let rondo = open();
        let category = rondo.add_category("Streaming".into(), 0).unwrap();
        let mut with_category = draft("Netflix");
        with_category.category_id = Some(category.id);
        let sub = rondo.add_subscription(with_category).unwrap();

        rondo.delete_category(category.id).unwrap();
        let reloaded = rondo.subscription(sub.id).unwrap().unwrap();
        assert_eq!(reloaded.category_id, None);
    }

    #[test]
    fn a_category_needs_a_name() {
        let rondo = open();
        assert!(matches!(
            rondo.add_category("   ".into(), 0),
            Err(RondoError::InvalidInput { .. })
        ));
    }

    #[test]
    fn spending_totals_stay_separate_per_currency_and_skip_archived() {
        let rondo = open();
        // 15.90 monthly and 120 yearly in USD, plus 8 monthly in CNY.
        rondo.add_subscription(draft("Netflix")).unwrap();
        let mut yearly = draft("Copilot");
        yearly.amount = DecimalString(Decimal::from_str("120").unwrap());
        yearly.cycle_unit = CycleUnit::Year;
        rondo.add_subscription(yearly).unwrap();
        let mut cny = draft("Music");
        cny.amount = DecimalString(Decimal::from_str("8").unwrap());
        cny.currency = "CNY".into();
        rondo.add_subscription(cny).unwrap();
        let archived = rondo.add_subscription(draft("Gone")).unwrap();
        rondo.set_archived(archived.id, true).unwrap();

        let summary = rondo.spending_summary().unwrap();
        assert_eq!(summary.len(), 2, "currencies are never mixed");
        let cny = &summary[0];
        assert_eq!(cny.currency, "CNY");
        assert_eq!(cny.monthly.0.to_string(), "8");
        let usd = &summary[1];
        assert_eq!(usd.currency, "USD");
        assert_eq!(usd.subscription_count, 2, "the archived one is left out");
        // 15.90 a month plus 120 a year is 25.90 a month.
        assert_eq!(usd.monthly.0.to_string(), "25.90");
    }

    #[test]
    fn the_template_catalogue_is_available_without_a_database() {
        let templates = crate::records::service_templates();
        assert!(!templates.is_empty());
        assert!(templates.iter().any(|t| t.name == "Netflix"));
    }

    #[test]
    fn archiving_an_unknown_id_says_so() {
        let rondo = open();
        assert!(matches!(
            rondo.set_archived(Uuid::now_v7(), true),
            Err(RondoError::InvalidInput { .. })
        ));
    }
}
