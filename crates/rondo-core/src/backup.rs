//! JSON backup: exporting a whole database and restoring one.
//!
//! Until device sync exists this is the only way to move data between
//! machines or keep a copy, so the format is plain JSON a human can read
//! and a later version can migrate: a version number, an export time, and
//! the entities exactly as the domain model defines them.

use std::collections::HashSet;

use jiff::Timestamp;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::{Error, Result};
use crate::model::{Category, Subscription};
use crate::store::Store;

/// Format version written by this build.
///
/// Import refuses anything newer, since this build cannot know what the
/// unknown fields mean. Older versions would be migrated here once a
/// second version exists.
pub const FORMAT_VERSION: u32 = 1;

/// A complete export of one Rondo database.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Backup {
    /// Format version; see [`FORMAT_VERSION`].
    pub version: u32,
    /// When the export was taken (UTC), for the reader's orientation only.
    pub exported_at: Timestamp,
    /// Categories, ordered as the store lists them.
    pub categories: Vec<Category>,
    /// Subscriptions of every status, active and archived alike.
    pub subscriptions: Vec<Subscription>,
}

/// What an import changed.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ImportReport {
    pub categories_added: usize,
    pub categories_updated: usize,
    pub subscriptions_added: usize,
    pub subscriptions_updated: usize,
}

/// Reads the whole store into a [`Backup`].
pub fn export(store: &Store) -> Result<Backup> {
    Ok(Backup {
        version: FORMAT_VERSION,
        exported_at: Timestamp::now(),
        categories: store.categories()?,
        subscriptions: store.subscriptions(None)?,
    })
}

/// Serializes the whole store as indented JSON.
pub fn export_json(store: &Store) -> Result<String> {
    serde_json::to_string_pretty(&export(store)?)
        .map_err(|e| Error::Corrupt(format!("serializing backup: {e}")))
}

/// Merges a backup into the store, keyed by entity id.
///
/// Entries already present are overwritten with the backed-up values,
/// timestamps included; entries only in the store are left alone. Nothing
/// is ever deleted, so importing the wrong file cannot destroy data, and
/// importing the same file twice changes nothing the second time.
///
/// The whole import is one transaction: on any failure the store is left
/// exactly as it was.
pub fn import(store: &Store, backup: &Backup) -> Result<ImportReport> {
    if backup.version > FORMAT_VERSION {
        return Err(Error::Corrupt(format!(
            "backup version {} is newer than supported version {FORMAT_VERSION}",
            backup.version
        )));
    }

    // Categories are written before subscriptions so references resolve,
    // but a backup may still point at a category it does not carry. Reject
    // that up front rather than letting a foreign-key error escape halfway
    // through, where the message would name a constraint, not the cause.
    let mut known: HashSet<Uuid> = backup.categories.iter().map(|c| c.id).collect();
    known.extend(store.categories()?.iter().map(|c| c.id));
    if let Some(sub) = backup
        .subscriptions
        .iter()
        .find(|s| s.category_id.is_some_and(|id| !known.contains(&id)))
    {
        return Err(Error::Corrupt(format!(
            "subscription {} references unknown category {}",
            sub.id,
            sub.category_id.expect("filtered on Some")
        )));
    }

    let tx = store.transaction()?;
    let mut report = ImportReport::default();
    for category in &backup.categories {
        if store.upsert_category(category)? {
            report.categories_added += 1;
        } else {
            report.categories_updated += 1;
        }
    }
    for sub in &backup.subscriptions {
        if store.upsert_subscription(sub)? {
            report.subscriptions_added += 1;
        } else {
            report.subscriptions_updated += 1;
        }
    }
    tx.commit()?;
    Ok(report)
}

/// Parses JSON and merges it into the store; see [`import`].
pub fn import_json(store: &Store, json: &str) -> Result<ImportReport> {
    let backup: Backup =
        serde_json::from_str(json).map_err(|e| Error::Corrupt(format!("parsing backup: {e}")))?;
    import(store, &backup)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{BillingCycle, CycleUnit, Money, SubscriptionStatus};
    use jiff::civil::Date;
    use rust_decimal::Decimal;
    use std::str::FromStr;

    fn sub(name: &str) -> Subscription {
        Subscription::new(
            name,
            Money::new(Decimal::from_str("15.99").unwrap(), "USD").unwrap(),
            BillingCycle::new(1, CycleUnit::Month).unwrap(),
            Date::constant(2026, 1, 31),
        )
        .unwrap()
    }

    fn populated() -> (Store, Category, Subscription) {
        let store = Store::open_in_memory().unwrap();
        let category = Category::new("Streaming", 0).unwrap();
        store.insert_category(&category).unwrap();
        let mut s = sub("Netflix");
        s.category_id = Some(category.id);
        s.notes = Some("family plan".into());
        store.insert_subscription(&s).unwrap();
        (store, category, s)
    }

    #[test]
    fn export_then_import_reproduces_the_database() {
        let (source, category, subscription) = populated();
        let mut archived = sub("Old Service");
        archived.status = SubscriptionStatus::Archived;
        source.insert_subscription(&archived).unwrap();

        let json = export_json(&source).unwrap();

        let target = Store::open_in_memory().unwrap();
        let report = import_json(&target, &json).unwrap();
        assert_eq!(report.categories_added, 1);
        assert_eq!(report.subscriptions_added, 2);
        assert_eq!(report.subscriptions_updated, 0);

        assert_eq!(target.categories().unwrap(), vec![category]);
        // Archived entries travel too, with every field intact.
        assert_eq!(
            target.subscription(subscription.id).unwrap().unwrap(),
            subscription
        );
        assert_eq!(
            target.subscription(archived.id).unwrap().unwrap().status,
            SubscriptionStatus::Archived
        );
    }

    #[test]
    fn importing_the_same_backup_twice_changes_nothing() {
        let (source, _, _) = populated();
        let json = export_json(&source).unwrap();
        let target = Store::open_in_memory().unwrap();

        import_json(&target, &json).unwrap();
        let second = import_json(&target, &json).unwrap();
        assert_eq!(second.categories_added, 0);
        assert_eq!(second.categories_updated, 1);
        assert_eq!(second.subscriptions_added, 0);
        assert_eq!(second.subscriptions_updated, 1);
        assert_eq!(target.subscriptions(None).unwrap().len(), 1);
    }

    #[test]
    fn import_preserves_timestamps_rather_than_refreshing_them() {
        let (source, _, subscription) = populated();
        let json = export_json(&source).unwrap();
        let target = Store::open_in_memory().unwrap();
        import_json(&target, &json).unwrap();

        let restored = target.subscription(subscription.id).unwrap().unwrap();
        assert_eq!(restored.created_at, subscription.created_at);
        assert_eq!(restored.updated_at, subscription.updated_at);
    }

    #[test]
    fn import_keeps_entries_the_backup_does_not_mention() {
        let (source, _, _) = populated();
        let json = export_json(&source).unwrap();

        let target = Store::open_in_memory().unwrap();
        let local = sub("Local Only");
        target.insert_subscription(&local).unwrap();
        import_json(&target, &json).unwrap();

        assert!(target.subscription(local.id).unwrap().is_some());
        assert_eq!(target.subscriptions(None).unwrap().len(), 2);
    }

    #[test]
    fn import_rejects_a_newer_format_version() {
        let (source, _, _) = populated();
        let mut backup = export(&source).unwrap();
        backup.version = FORMAT_VERSION + 1;
        let target = Store::open_in_memory().unwrap();

        assert!(import(&target, &backup).is_err());
        assert!(target.subscriptions(None).unwrap().is_empty());
    }

    #[test]
    fn import_rejects_a_subscription_with_a_dangling_category() {
        let (source, _, _) = populated();
        let mut backup = export(&source).unwrap();
        backup.categories.clear();
        let target = Store::open_in_memory().unwrap();

        assert!(import(&target, &backup).is_err());
        // The rejection happens before any write.
        assert!(target.subscriptions(None).unwrap().is_empty());
    }

    #[test]
    fn import_rejects_malformed_json_and_invalid_values() {
        let store = Store::open_in_memory().unwrap();
        assert!(import_json(&store, "not json").is_err());
        // A cycle count of zero is invalid; the model rejects it on the way
        // in rather than storing something unusable.
        let bad = r#"{"version":1,"exported_at":"2026-08-20T00:00:00Z","categories":[],
            "subscriptions":[{"id":"01991b9a-0000-7000-8000-000000000000","name":"x",
            "notes":null,"template_id":null,"price":{"amount":"1","currency":"USD"},
            "cycle":{"count":0,"unit":"month"},"first_billing_date":"2026-01-01",
            "reminder_lead_days":3,"category_id":null,"status":"active",
            "created_at":"2026-08-20T00:00:00Z","updated_at":"2026-08-20T00:00:00Z"}]}"#;
        assert!(import_json(&store, bad).is_err());
        assert!(store.subscriptions(None).unwrap().is_empty());
    }
}
