//! SQLite persistence for subscriptions and categories.
//!
//! Amounts, dates, and timestamps are stored as text in their canonical
//! string forms (exact decimal, ISO date, RFC 3339 UTC); every row read
//! back passes through the validating domain constructors, so a database
//! edited by other tools cannot smuggle invalid state into the model.

use std::path::Path;
use std::sync::LazyLock;

use jiff::Timestamp;
use rusqlite::{Connection, Row, params};
use rusqlite_migration::{M, Migrations};
use uuid::Uuid;

use crate::error::{Error, Result};
use crate::model::{BillingCycle, Category, CycleUnit, Money, Subscription, SubscriptionStatus};

/// Handle to one Rondo database.
///
/// Not thread-safe by itself; wrap it in a lock to share across threads.
pub struct Store {
    conn: Connection,
}

impl Store {
    /// Opens (creating if needed) the database at `path` and migrates it.
    pub fn open(path: &Path) -> Result<Self> {
        Self::from_connection(Connection::open(path)?)
    }

    /// Opens a fresh in-memory database; used by tests and previews.
    pub fn open_in_memory() -> Result<Self> {
        Self::from_connection(Connection::open_in_memory()?)
    }

    fn from_connection(mut conn: Connection) -> Result<Self> {
        // Foreign keys are per-connection in SQLite and off by default.
        conn.pragma_update(None, "foreign_keys", "ON")?;
        MIGRATIONS.to_latest(&mut conn)?;
        Ok(Self { conn })
    }

    // -- subscriptions --

    /// Inserts a subscription exactly as given.
    pub fn insert_subscription(&self, sub: &Subscription) -> Result<()> {
        self.conn.execute(
            "INSERT INTO subscription (id, name, notes, template_id, amount, currency,
                 cycle_count, cycle_unit, first_billing_date, reminder_lead_days,
                 category_id, status, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)",
            params![
                sub.id.to_string(),
                sub.name,
                sub.notes,
                sub.template_id,
                sub.price.amount().to_string(),
                sub.price.currency(),
                sub.cycle.count(),
                unit_str(sub.cycle.unit()),
                sub.first_billing_date.to_string(),
                sub.reminder_lead_days,
                sub.category_id.map(|id| id.to_string()),
                status_str(sub.status),
                sub.created_at.to_string(),
                sub.updated_at.to_string(),
            ],
        )?;
        Ok(())
    }

    /// Overwrites the stored subscription and refreshes its `updated_at`.
    ///
    /// Returns the value as persisted (input with the new timestamp).
    /// Fails with [`Error::Corrupt`] if no row has this id.
    pub fn update_subscription(&self, sub: &Subscription) -> Result<Subscription> {
        let mut stored = sub.clone();
        stored.updated_at = Timestamp::now();
        let changed = self.conn.execute(
            "UPDATE subscription SET name = ?2, notes = ?3, template_id = ?4,
                 amount = ?5, currency = ?6, cycle_count = ?7, cycle_unit = ?8,
                 first_billing_date = ?9, reminder_lead_days = ?10, category_id = ?11,
                 status = ?12, created_at = ?13, updated_at = ?14
             WHERE id = ?1",
            params![
                stored.id.to_string(),
                stored.name,
                stored.notes,
                stored.template_id,
                stored.price.amount().to_string(),
                stored.price.currency(),
                stored.cycle.count(),
                unit_str(stored.cycle.unit()),
                stored.first_billing_date.to_string(),
                stored.reminder_lead_days,
                stored.category_id.map(|id| id.to_string()),
                status_str(stored.status),
                stored.created_at.to_string(),
                stored.updated_at.to_string(),
            ],
        )?;
        if changed == 0 {
            return Err(Error::Corrupt(format!(
                "no subscription with id {} to update",
                stored.id
            )));
        }
        Ok(stored)
    }

    /// Deletes a subscription; returns whether a row existed.
    pub fn delete_subscription(&self, id: Uuid) -> Result<bool> {
        let changed = self
            .conn
            .execute("DELETE FROM subscription WHERE id = ?1", [id.to_string()])?;
        Ok(changed > 0)
    }

    /// Loads one subscription by id.
    pub fn subscription(&self, id: Uuid) -> Result<Option<Subscription>> {
        let mut stmt = self
            .conn
            .prepare("SELECT * FROM subscription WHERE id = ?1")?;
        let mut rows = stmt.query([id.to_string()])?;
        match rows.next()? {
            Some(row) => Ok(Some(subscription_from_row(row)?)),
            None => Ok(None),
        }
    }

    /// Lists subscriptions, optionally filtered by status, ordered by name.
    ///
    /// Ordering by next billing date needs a reference day, so it belongs to
    /// the caller (via [`crate::cycle::next_billing_date`]), not to SQL.
    pub fn subscriptions(&self, status: Option<SubscriptionStatus>) -> Result<Vec<Subscription>> {
        let (sql, args): (&str, Vec<String>) = match status {
            Some(s) => (
                "SELECT * FROM subscription WHERE status = ?1 ORDER BY name COLLATE NOCASE",
                vec![status_str(s).to_owned()],
            ),
            None => (
                "SELECT * FROM subscription ORDER BY name COLLATE NOCASE",
                Vec::new(),
            ),
        };
        let mut stmt = self.conn.prepare(sql)?;
        let mut rows = stmt.query(rusqlite::params_from_iter(args))?;
        let mut subs = Vec::new();
        while let Some(row) = rows.next()? {
            subs.push(subscription_from_row(row)?);
        }
        Ok(subs)
    }

    // -- categories --

    /// Inserts a category exactly as given.
    pub fn insert_category(&self, category: &Category) -> Result<()> {
        self.conn.execute(
            "INSERT INTO category (id, name, sort_order) VALUES (?1, ?2, ?3)",
            params![category.id.to_string(), category.name, category.sort_order],
        )?;
        Ok(())
    }

    /// Overwrites the stored category. Fails with [`Error::Corrupt`] if no
    /// row has this id.
    pub fn update_category(&self, category: &Category) -> Result<()> {
        let changed = self.conn.execute(
            "UPDATE category SET name = ?2, sort_order = ?3 WHERE id = ?1",
            params![category.id.to_string(), category.name, category.sort_order],
        )?;
        if changed == 0 {
            return Err(Error::Corrupt(format!(
                "no category with id {} to update",
                category.id
            )));
        }
        Ok(())
    }

    /// Deletes a category; subscriptions keep existing with no category
    /// (`ON DELETE SET NULL`). Returns whether a row existed.
    pub fn delete_category(&self, id: Uuid) -> Result<bool> {
        let changed = self
            .conn
            .execute("DELETE FROM category WHERE id = ?1", [id.to_string()])?;
        Ok(changed > 0)
    }

    /// Lists categories ordered by `sort_order`, then name.
    pub fn categories(&self) -> Result<Vec<Category>> {
        let mut stmt = self
            .conn
            .prepare("SELECT * FROM category ORDER BY sort_order, name COLLATE NOCASE")?;
        let mut rows = stmt.query([])?;
        let mut categories = Vec::new();
        while let Some(row) = rows.next()? {
            categories.push(Category {
                id: parse_uuid(row.get::<_, String>("id")?)?,
                name: row.get("name")?,
                sort_order: row.get("sort_order")?,
            });
        }
        Ok(categories)
    }
}

/// The ordered schema migrations, applied on every open.
///
/// Each entry is immutable once released: a mistake is corrected by a new
/// migration, never by editing an old one, since databases that already ran
/// it would never see the edit.
static MIGRATIONS: LazyLock<Migrations<'static>> =
    LazyLock::new(|| Migrations::new(vec![M::up(include_str!("../migrations/001-initial.sql"))]));

/// Rebuilds a [`Subscription`] from a row, re-validating every invariant.
fn subscription_from_row(row: &Row<'_>) -> Result<Subscription> {
    let amount: String = row.get("amount")?;
    let currency: String = row.get("currency")?;
    let price = Money::new(
        amount
            .parse()
            .map_err(|e| Error::Corrupt(format!("amount {amount:?}: {e}")))?,
        &currency,
    )?;
    let cycle = BillingCycle::new(
        row.get("cycle_count")?,
        parse_unit(&row.get::<_, String>("cycle_unit")?)?,
    )?;
    Ok(Subscription {
        id: parse_uuid(row.get::<_, String>("id")?)?,
        name: row.get("name")?,
        notes: row.get("notes")?,
        template_id: row.get("template_id")?,
        price,
        cycle,
        first_billing_date: parse_text(row.get::<_, String>("first_billing_date")?)?,
        reminder_lead_days: row.get("reminder_lead_days")?,
        category_id: row
            .get::<_, Option<String>>("category_id")?
            .map(parse_uuid)
            .transpose()?,
        status: parse_status(&row.get::<_, String>("status")?)?,
        created_at: parse_text(row.get::<_, String>("created_at")?)?,
        updated_at: parse_text(row.get::<_, String>("updated_at")?)?,
    })
}

fn unit_str(unit: CycleUnit) -> &'static str {
    match unit {
        CycleUnit::Day => "day",
        CycleUnit::Week => "week",
        CycleUnit::Month => "month",
        CycleUnit::Year => "year",
    }
}

fn parse_unit(s: &str) -> Result<CycleUnit> {
    match s {
        "day" => Ok(CycleUnit::Day),
        "week" => Ok(CycleUnit::Week),
        "month" => Ok(CycleUnit::Month),
        "year" => Ok(CycleUnit::Year),
        other => Err(Error::Corrupt(format!("unknown cycle unit {other:?}"))),
    }
}

fn status_str(status: SubscriptionStatus) -> &'static str {
    match status {
        SubscriptionStatus::Active => "active",
        SubscriptionStatus::Archived => "archived",
    }
}

fn parse_status(s: &str) -> Result<SubscriptionStatus> {
    match s {
        "active" => Ok(SubscriptionStatus::Active),
        "archived" => Ok(SubscriptionStatus::Archived),
        other => Err(Error::Corrupt(format!("unknown status {other:?}"))),
    }
}

fn parse_uuid(s: String) -> Result<Uuid> {
    s.parse()
        .map_err(|e| Error::Corrupt(format!("uuid {s:?}: {e}")))
}

/// Parses any `FromStr` field, mapping failures to [`Error::Corrupt`].
fn parse_text<T>(s: String) -> Result<T>
where
    T: std::str::FromStr,
    T::Err: std::fmt::Display,
{
    s.parse().map_err(|e| Error::Corrupt(format!("{s:?}: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use jiff::civil::Date;
    use rusqlite_migration::SchemaVersion;
    use rust_decimal::Decimal;
    use std::num::NonZeroUsize;
    use std::str::FromStr;

    fn sample() -> Subscription {
        Subscription::new(
            "Netflix",
            Money::new(Decimal::from_str("15.99").unwrap(), "USD").unwrap(),
            BillingCycle::new(1, CycleUnit::Month).unwrap(),
            Date::constant(2026, 1, 31),
        )
        .unwrap()
    }

    #[test]
    fn migrations_are_valid_and_reach_the_latest_version() {
        // Catches a malformed or out-of-order migration at test time rather
        // than on a user's database.
        MIGRATIONS.validate().unwrap();
        let store = Store::open_in_memory().unwrap();
        assert_eq!(
            MIGRATIONS.current_version(&store.conn).unwrap(),
            SchemaVersion::Inside(NonZeroUsize::new(1).unwrap())
        );
    }

    #[test]
    fn subscription_round_trips_exactly() {
        let store = Store::open_in_memory().unwrap();
        let mut sub = sample();
        sub.notes = Some("family plan".into());
        store.insert_subscription(&sub).unwrap();
        assert_eq!(store.subscription(sub.id).unwrap().unwrap(), sub);
        assert!(store.subscription(Uuid::now_v7()).unwrap().is_none());
    }

    #[test]
    fn update_refreshes_updated_at_and_persists() {
        let store = Store::open_in_memory().unwrap();
        let mut sub = sample();
        store.insert_subscription(&sub).unwrap();
        sub.name = "Netflix Premium".into();
        let stored = store.update_subscription(&sub).unwrap();
        assert!(stored.updated_at >= sub.updated_at);
        assert_eq!(store.subscription(sub.id).unwrap().unwrap(), stored);
        // Updating a missing row is corruption, not silence.
        assert!(store.update_subscription(&sample()).is_err());
    }

    #[test]
    fn delete_reports_whether_a_row_existed() {
        let store = Store::open_in_memory().unwrap();
        let sub = sample();
        store.insert_subscription(&sub).unwrap();
        assert!(store.delete_subscription(sub.id).unwrap());
        assert!(!store.delete_subscription(sub.id).unwrap());
    }

    #[test]
    fn listing_filters_by_status_and_orders_by_name() {
        let store = Store::open_in_memory().unwrap();
        let mut a = sample();
        a.name = "beta".into();
        let mut b = sample();
        b.name = "Alpha".into();
        let mut c = sample();
        c.name = "gamma".into();
        c.status = SubscriptionStatus::Archived;
        for s in [&a, &b, &c] {
            store.insert_subscription(s).unwrap();
        }
        let active = store
            .subscriptions(Some(SubscriptionStatus::Active))
            .unwrap();
        assert_eq!(
            active.iter().map(|s| s.name.as_str()).collect::<Vec<_>>(),
            vec!["Alpha", "beta"]
        );
        assert_eq!(store.subscriptions(None).unwrap().len(), 3);
    }

    #[test]
    fn deleting_a_category_detaches_subscriptions() {
        let store = Store::open_in_memory().unwrap();
        let cat = Category::new("Streaming", 0).unwrap();
        store.insert_category(&cat).unwrap();
        let mut sub = sample();
        sub.category_id = Some(cat.id);
        store.insert_subscription(&sub).unwrap();

        assert!(store.delete_category(cat.id).unwrap());
        let reloaded = store.subscription(sub.id).unwrap().unwrap();
        assert_eq!(reloaded.category_id, None);
    }

    #[test]
    fn categories_order_by_sort_order_then_name() {
        let store = Store::open_in_memory().unwrap();
        let mut first = Category::new("b-second", 1).unwrap();
        let a = Category::new("a-third", 2).unwrap();
        let z = Category::new("z-first", 0).unwrap();
        for c in [&first, &a, &z] {
            store.insert_category(c).unwrap();
        }
        first.name = "b-renamed".into();
        store.update_category(&first).unwrap();
        let names: Vec<String> = store
            .categories()
            .unwrap()
            .into_iter()
            .map(|c| c.name)
            .collect();
        assert_eq!(names, vec!["z-first", "b-renamed", "a-third"]);
    }

    #[test]
    fn data_survives_reopening_the_file() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("rondo.sqlite3");
        let sub = sample();
        {
            let store = Store::open(&path).unwrap();
            store.insert_subscription(&sub).unwrap();
        }
        let store = Store::open(&path).unwrap();
        assert_eq!(store.subscription(sub.id).unwrap().unwrap(), sub);
    }
}
