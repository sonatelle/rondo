//! JSON backup: exporting a whole database and restoring one.
//!
//! Until device sync exists this is the only way to move data between
//! machines or keep a copy, so the format is plain JSON a human can read
//! and a later version can migrate: a version number, an export time, and
//! the entities exactly as the domain model defines them.

use std::collections::HashSet;

use jiff::Timestamp;
use jiff::tz::TimeZone;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::{Error, Result};
use crate::model::{Category, Price, Subscription};
use crate::store::Store;

/// Format version written by this build.
///
/// Import refuses anything newer, since this build cannot know what the
/// unknown fields mean, and migrates anything older.
///
/// Version 2 added the price history. A version 1 file carries one price
/// per subscription and no history at all, so importing one opens a history
/// with that price, effective from the first charge - the same thing the
/// schema migration does to a version 1 database.
pub const FORMAT_VERSION: u32 = 2;

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
    ///
    /// Each carries a `price`, which in a version 2 file is a reading of
    /// the history taken when the export ran - there so that a person
    /// opening the file sees what a subscription costs without working it
    /// out from `prices`. Restoring ignores it; `prices` is what is
    /// written back. In a version 1 file it is the only price there is,
    /// and restoring does use it.
    pub subscriptions: Vec<Subscription>,
    /// Every price ever recorded, for every subscription.
    ///
    /// Absent from version 1 files, hence the default: an empty history is
    /// the signal to rebuild one from each subscription's own price.
    #[serde(default)]
    pub prices: Vec<Price>,
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
///
/// Subscriptions are priced as of the export instant in UTC. That is the
/// one place the core picks a day for itself rather than being handed one,
/// and it is safe here because the value is for a human reading the file:
/// what is restored comes from `prices`, which has no such reading in it.
pub fn export(store: &Store) -> Result<Backup> {
    let exported_at = Timestamp::now();
    let today = exported_at.to_zoned(TimeZone::UTC).date();
    let mut prices: Vec<Price> = store
        .all_price_histories()?
        .into_values()
        .flatten()
        .collect();
    // Grouped by subscription and then by date, so the file reads in the
    // order a person would expect and two exports of one database differ
    // only where the data does.
    prices.sort_by(|a, b| {
        a.subscription_id
            .cmp(&b.subscription_id)
            .then(a.effective_from.cmp(&b.effective_from))
    });
    Ok(Backup {
        version: FORMAT_VERSION,
        exported_at,
        categories: store.categories()?,
        subscriptions: store.subscriptions(None, today)?,
        prices,
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

    let prices = prices_of(backup);

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
    // After the subscriptions, so the foreign key resolves.
    for price in &prices {
        store.upsert_price(price)?;
    }
    tx.commit()?;
    Ok(report)
}

/// The price history a backup carries, rebuilding it when the file predates
/// histories entirely.
///
/// A version 1 file has one price per subscription and no dates for it, so
/// the first charge is the only day it can be said to have taken effect -
/// the same reconstruction the schema migration performs, which keeps a
/// database restored from a file identical to one migrated in place.
///
/// The synthesized id is the subscription's own, so restoring the same file
/// twice writes the same row rather than a second copy of it.
fn prices_of(backup: &Backup) -> Vec<Price> {
    if !backup.prices.is_empty() {
        return backup.prices.clone();
    }
    backup
        .subscriptions
        .iter()
        .map(|sub| Price {
            id: sub.id,
            subscription_id: sub.id,
            effective_from: sub.first_billing_date,
            amount: sub.price.clone(),
            created_at: sub.created_at,
            updated_at: sub.updated_at,
        })
        .collect()
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

    /// The day these tests read prices as of. Later than every sample's
    /// first charge, so the price in force is the one that was stored.
    const TODAY: Date = Date::constant(2026, 6, 1);

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
            target
                .subscription(subscription.id, TODAY)
                .unwrap()
                .unwrap(),
            subscription
        );
        assert_eq!(
            target
                .subscription(archived.id, TODAY)
                .unwrap()
                .unwrap()
                .status,
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
        assert_eq!(target.subscriptions(None, TODAY).unwrap().len(), 1);
    }

    #[test]
    fn import_preserves_timestamps_rather_than_refreshing_them() {
        let (source, _, subscription) = populated();
        let json = export_json(&source).unwrap();
        let target = Store::open_in_memory().unwrap();
        import_json(&target, &json).unwrap();

        let restored = target
            .subscription(subscription.id, TODAY)
            .unwrap()
            .unwrap();
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

        assert!(target.subscription(local.id, TODAY).unwrap().is_some());
        assert_eq!(target.subscriptions(None, TODAY).unwrap().len(), 2);
    }

    #[test]
    fn import_rejects_a_newer_format_version() {
        let (source, _, _) = populated();
        let mut backup = export(&source).unwrap();
        backup.version = FORMAT_VERSION + 1;
        let target = Store::open_in_memory().unwrap();

        assert!(import(&target, &backup).is_err());
        assert!(target.subscriptions(None, TODAY).unwrap().is_empty());
    }

    #[test]
    fn import_rejects_a_subscription_with_a_dangling_category() {
        let (source, _, _) = populated();
        let mut backup = export(&source).unwrap();
        backup.categories.clear();
        let target = Store::open_in_memory().unwrap();

        assert!(import(&target, &backup).is_err());
        // The rejection happens before any write.
        assert!(target.subscriptions(None, TODAY).unwrap().is_empty());
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
        assert!(store.subscriptions(None, TODAY).unwrap().is_empty());
    }

    /// A version 1 file, shaped like one this project actually exported:
    /// several currencies, an amount written without decimals, a template
    /// on one subscription and none on the others, and first charges that
    /// have not happened yet.
    ///
    /// It is the compatibility promise in a test. Nothing else here reads a
    /// file this build cannot write.
    const V1_BACKUP: &str = r#"{
      "version": 1,
      "exported_at": "2026-09-02T06:38:36.987055Z",
      "categories": [],
      "subscriptions": [
        {
          "id": "01a0420c-6188-7043-bf96-3a84810c2657",
          "name": "ChatGPT", "notes": "billed to the store", "template_id": "chatgpt",
          "price": {"amount": "499.99", "currency": "TRY"},
          "cycle": {"count": 1, "unit": "month"},
          "first_billing_date": "2026-09-20", "reminder_lead_days": 3,
          "category_id": null, "status": "active",
          "created_at": "2026-08-27T07:08:22.792346Z",
          "updated_at": "2026-08-27T10:56:18.537133Z"
        },
        {
          "id": "01a032c9-6007-7222-b01a-0985ee775ab8",
          "name": "Claude", "notes": null, "template_id": null,
          "price": {"amount": "20", "currency": "USD"},
          "cycle": {"count": 1, "unit": "month"},
          "first_billing_date": "2026-08-30", "reminder_lead_days": 3,
          "category_id": null, "status": "active",
          "created_at": "2026-08-24T08:00:53.255992Z",
          "updated_at": "2026-08-28T06:15:34.117719Z"
        },
        {
          "id": "01a0420e-9876-7e83-a3e0-5fbc791432a0",
          "name": "Grok", "notes": null, "template_id": null,
          "price": {"amount": "700", "currency": "INR"},
          "cycle": {"count": 1, "unit": "month"},
          "first_billing_date": "2026-09-18", "reminder_lead_days": 3,
          "category_id": null, "status": "active",
          "created_at": "2026-08-27T07:10:47.926811Z",
          "updated_at": "2026-08-27T07:10:47.926811Z"
        }
      ]
    }"#;

    #[test]
    fn a_version_one_file_restores_with_a_history_of_its_one_price() {
        let store = Store::open_in_memory().unwrap();
        let report = import_json(&store, V1_BACKUP).unwrap();
        assert_eq!(report.subscriptions_added, 3);

        let subs = store.subscriptions(None, TODAY).unwrap();
        assert_eq!(subs.len(), 3);
        for sub in &subs {
            let history = store.price_history(sub.id).unwrap();
            assert_eq!(history.len(), 1, "{} gained the wrong history", sub.name);
            assert_eq!(history[0].effective_from, sub.first_billing_date);
            assert_eq!(history[0].amount, sub.price);
            // A restore keeps the file's timestamps; a synthesized price
            // inherits them rather than claiming to be new.
            assert_eq!(history[0].created_at, sub.created_at);
        }

        let by_name = |name: &str| subs.iter().find(|s| s.name == name).unwrap().clone();
        // Amounts survive as written: "20" must not come back as "20.00",
        // and 499.99 must not come back as a float's idea of it.
        assert_eq!(by_name("Claude").price.amount().to_string(), "20");
        assert_eq!(by_name("ChatGPT").price.amount().to_string(), "499.99");
        assert_eq!(by_name("Grok").price.currency(), "INR");
        assert_eq!(by_name("ChatGPT").template_id.as_deref(), Some("chatgpt"));
    }

    /// Restoring the same version 1 file twice must leave one history, not
    /// two: the synthesized price id is derived from the subscription's, so
    /// the second pass overwrites the first rather than adding to it.
    #[test]
    fn restoring_a_version_one_file_twice_changes_nothing_the_second_time() {
        let store = Store::open_in_memory().unwrap();
        import_json(&store, V1_BACKUP).unwrap();
        let again = import_json(&store, V1_BACKUP).unwrap();
        assert_eq!(again.subscriptions_added, 0);
        assert_eq!(again.subscriptions_updated, 3);

        for sub in store.subscriptions(None, TODAY).unwrap() {
            assert_eq!(store.price_history(sub.id).unwrap().len(), 1);
        }
    }

    /// A file this build writes, read back by this build, with a history of
    /// more than one entry - the case a version 1 file cannot express.
    #[test]
    fn a_rise_survives_a_round_trip() {
        let source = Store::open_in_memory().unwrap();
        let subscription = sub("Netflix");
        source.insert_subscription(&subscription).unwrap();
        source
            .add_price_change(
                subscription.id,
                Money::new(Decimal::from_str("19.99").unwrap(), "USD").unwrap(),
                Date::constant(2026, 4, 1),
            )
            .unwrap();

        let json = export_json(&source).unwrap();
        let target = Store::open_in_memory().unwrap();
        import_json(&target, &json).unwrap();

        let history = target.price_history(subscription.id).unwrap();
        assert_eq!(history.len(), 2);
        assert_eq!(history[0].amount.amount().to_string(), "15.99");
        assert_eq!(history[1].amount.amount().to_string(), "19.99");
        assert_eq!(history[1].effective_from, Date::constant(2026, 4, 1));
        assert_eq!(
            source.price_history(subscription.id).unwrap(),
            history,
            "a round trip must change nothing at all"
        );
    }

    #[test]
    fn a_file_from_a_future_version_is_still_refused() {
        let store = Store::open_in_memory().unwrap();
        let ahead = V1_BACKUP.replace("\"version\": 1", "\"version\": 3");
        assert!(import_json(&store, &ahead).is_err());
        assert!(store.subscriptions(None, TODAY).unwrap().is_empty());
    }
}
