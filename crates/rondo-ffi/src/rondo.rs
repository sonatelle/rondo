//! The object a frontend holds and calls into.

use std::path::PathBuf;
use std::sync::{Arc, Mutex, MutexGuard};

use rondo_core::Store;
use rondo_core::model::{
    BillingCycle, Money, Subscription as CoreSubscription, SubscriptionStatus,
};
use uuid::Uuid;

use crate::error::{Result, RondoError};
use crate::records::Subscription;
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
    fn archiving_an_unknown_id_says_so() {
        let rondo = open();
        assert!(matches!(
            rondo.set_archived(Uuid::now_v7(), true),
            Err(RondoError::InvalidInput { .. })
        ));
    }
}
