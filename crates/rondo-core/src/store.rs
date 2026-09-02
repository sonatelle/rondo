//! SQLite persistence for subscriptions and categories.
//!
//! Amounts, dates, and timestamps are stored as text in their canonical
//! string forms (exact decimal, ISO date, RFC 3339 UTC); every row read
//! back passes through the validating domain constructors, so a database
//! edited by other tools cannot smuggle invalid state into the model.

use std::collections::HashMap;
use std::path::Path;
use std::sync::LazyLock;
use std::time::Duration;

use jiff::Timestamp;
use jiff::civil::Date;
use rusqlite::{Connection, OptionalExtension, Row, params};
use rusqlite_migration::{M, Migrations};
use uuid::Uuid;

use crate::error::{Error, Result};
use crate::model;
use crate::model::{
    BillingCycle, Category, CycleUnit, Money, Price, Subscription, SubscriptionStatus,
};

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
        configure(&conn)?;
        MIGRATIONS.to_latest(&mut conn)?;
        Ok(Self { conn })
    }

    /// Starts a transaction on the shared connection.
    ///
    /// Callers must not nest these: the store holds one connection and
    /// SQLite has no nested transactions. Dropping without `commit` rolls
    /// back, which is how a failed multi-step write leaves no trace.
    pub(crate) fn transaction(&self) -> Result<rusqlite::Transaction<'_>> {
        Ok(self.conn.unchecked_transaction()?)
    }

    /// Reports whether a row with `id` exists in `table`.
    ///
    /// `table` is a literal chosen by this module, never user input.
    fn exists(&self, table: &str, id: &str) -> Result<bool> {
        let sql = format!("SELECT 1 FROM {table} WHERE id = ?1");
        let found = self
            .conn
            .query_row(&sql, [id], |_| Ok(()))
            .optional()?
            .is_some();
        Ok(found)
    }

    // -- subscriptions --

    /// Inserts a subscription, opening its price history with the price it
    /// carries, effective from its first charge.
    ///
    /// Both writes are one transaction: a subscription with no price would
    /// have no answer to what it costs, and nothing else in the store can
    /// repair that.
    pub fn insert_subscription(&self, sub: &Subscription) -> Result<()> {
        let tx = self.transaction()?;
        tx.execute(
            "INSERT INTO subscription (id, name, notes, template_id,
                 cycle_count, cycle_unit, first_billing_date, reminder_lead_days,
                 category_id, channel, account, payment_method_id,
                 status, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)",
            params![
                sub.id.to_string(),
                sub.name,
                sub.notes,
                sub.template_id,
                sub.cycle.count(),
                unit_str(sub.cycle.unit()),
                sub.first_billing_date.to_string(),
                sub.reminder_lead_days,
                sub.category_id.map(|id| id.to_string()),
                Option::<String>::None,
                Option::<String>::None,
                Option::<String>::None,
                status_str(sub.status),
                sub.created_at.to_string(),
                sub.updated_at.to_string(),
            ],
        )?;
        let opening = Price {
            id: sub.id,
            subscription_id: sub.id,
            effective_from: sub.first_billing_date,
            amount: sub.price.clone(),
            created_at: sub.created_at,
            updated_at: sub.updated_at,
        };
        insert_price(&tx, &opening)?;
        tx.commit()?;
        Ok(())
    }

    /// Every price in the store, grouped by subscription, earliest first.
    pub fn all_price_histories(&self) -> Result<HashMap<Uuid, Vec<Price>>> {
        let mut stmt = self
            .conn
            .prepare("SELECT * FROM subscription_price ORDER BY subscription_id, effective_from")?;
        let mut rows = stmt.query([])?;
        let mut histories: HashMap<Uuid, Vec<Price>> = HashMap::new();
        while let Some(row) = rows.next()? {
            let price = price_from_row(row)?;
            histories
                .entry(price.subscription_id)
                .or_default()
                .push(price);
        }
        Ok(histories)
    }

    /// Every price ever recorded for a subscription, earliest first.
    pub fn price_history(&self, subscription_id: Uuid) -> Result<Vec<Price>> {
        let mut stmt = self.conn.prepare(
            "SELECT * FROM subscription_price WHERE subscription_id = ?1
             ORDER BY effective_from",
        )?;
        let mut rows = stmt.query([subscription_id.to_string()])?;
        let mut prices = Vec::new();
        while let Some(row) = rows.next()? {
            prices.push(price_from_row(row)?);
        }
        Ok(prices)
    }

    /// Records that the price changed from `effective_from`.
    ///
    /// This is the rise, not the correction: earlier charges keep the price
    /// they were charged at. Correcting a price that was entered wrong is
    /// [`Self::correct_price`], which leaves no trace of a change that never
    /// happened.
    pub fn add_price_change(
        &self,
        subscription_id: Uuid,
        amount: Money,
        effective_from: Date,
    ) -> Result<Price> {
        let price = Price::new(subscription_id, amount, effective_from);
        insert_price(&self.conn, &price)?;
        Ok(price)
    }

    /// Overwrites one price entry in place, for when it was recorded wrong.
    ///
    /// Fails with [`Error::Corrupt`] if no entry has this id.
    pub fn correct_price(&self, price: &Price) -> Result<Price> {
        let mut stored = price.clone();
        stored.updated_at = Timestamp::now();
        let changed = self.conn.execute(
            "UPDATE subscription_price SET effective_from = ?2, amount = ?3,
                 currency = ?4, updated_at = ?5
             WHERE id = ?1",
            params![
                stored.id.to_string(),
                stored.effective_from.to_string(),
                stored.amount.amount().to_string(),
                stored.amount.currency(),
                stored.updated_at.to_string(),
            ],
        )?;
        if changed == 0 {
            return Err(Error::Corrupt(format!(
                "no price with id {} to correct",
                stored.id
            )));
        }
        Ok(stored)
    }

    /// Deletes one price entry; reports whether one was there.
    ///
    /// Refuses to remove the last entry, which would leave a subscription
    /// with no price at all.
    pub fn delete_price(&self, id: Uuid) -> Result<bool> {
        let owner: Option<String> = self
            .conn
            .query_row(
                "SELECT subscription_id FROM subscription_price WHERE id = ?1",
                [id.to_string()],
                |row| row.get(0),
            )
            .optional()?;
        let Some(owner) = owner else {
            return Ok(false);
        };
        let remaining: i64 = self.conn.query_row(
            "SELECT count(*) FROM subscription_price WHERE subscription_id = ?1",
            [&owner],
            |row| row.get(0),
        )?;
        if remaining <= 1 {
            return Err(Error::InvalidSubscription(
                "a subscription must keep at least one price".into(),
            ));
        }
        let changed = self.conn.execute(
            "DELETE FROM subscription_price WHERE id = ?1",
            [id.to_string()],
        )?;
        Ok(changed > 0)
    }

    /// Writes a price as given, inserting or overwriting by id.
    ///
    /// Preserves timestamps exactly, which is what restoring a backup must
    /// do. Returns whether the row was newly inserted.
    pub fn upsert_price(&self, price: &Price) -> Result<bool> {
        let inserted = !self.exists("subscription_price", &price.id.to_string())?;
        self.conn.execute(
            "INSERT INTO subscription_price (id, subscription_id, effective_from,
                 amount, currency, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(id) DO UPDATE SET
                 subscription_id = ?2, effective_from = ?3, amount = ?4,
                 currency = ?5, created_at = ?6, updated_at = ?7",
            params![
                price.id.to_string(),
                price.subscription_id.to_string(),
                price.effective_from.to_string(),
                price.amount.amount().to_string(),
                price.amount.currency(),
                price.created_at.to_string(),
                price.updated_at.to_string(),
            ],
        )?;
        Ok(inserted)
    }

    /// Overwrites the stored subscription and refreshes its `updated_at`.
    ///
    /// A changed price **corrects** the entry in force on `on` rather than
    /// recording a rise, because mistyping a price is common and a rise is
    /// rare. Recording a real change of price is
    /// [`Self::add_price_change`], which keeps what earlier charges cost.
    ///
    /// Returns the value as persisted (input with the new timestamp).
    /// Fails with [`Error::Corrupt`] if no row has this id.
    pub fn update_subscription(&self, sub: &Subscription, on: Date) -> Result<Subscription> {
        let mut stored = sub.clone();
        stored.updated_at = Timestamp::now();
        let tx = self.transaction()?;
        let changed = tx.execute(
            "UPDATE subscription SET name = ?2, notes = ?3, template_id = ?4,
                 cycle_count = ?5, cycle_unit = ?6,
                 first_billing_date = ?7, reminder_lead_days = ?8, category_id = ?9,
                 status = ?10, created_at = ?11, updated_at = ?12
             WHERE id = ?1",
            params![
                stored.id.to_string(),
                stored.name,
                stored.notes,
                stored.template_id,
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

        let history = self.price_history(stored.id)?;
        let applicable = model::price_on(&history, on)
            .ok_or_else(|| Error::Corrupt(format!("subscription {} has no price", stored.id)))?;
        if applicable.amount != stored.price {
            tx.execute(
                "UPDATE subscription_price SET amount = ?2, currency = ?3, updated_at = ?4
                 WHERE id = ?1",
                params![
                    applicable.id.to_string(),
                    stored.price.amount().to_string(),
                    stored.price.currency(),
                    stored.updated_at.to_string(),
                ],
            )?;
        }
        tx.commit()?;
        Ok(stored)
    }

    /// Writes a subscription as given, inserting or overwriting by id.
    ///
    /// Unlike [`Self::update_subscription`] this preserves `updated_at`
    /// exactly, which is what restoring a backup must do. Returns whether
    /// the row was newly inserted.
    ///
    /// Uses an explicit upsert rather than `INSERT OR REPLACE`, which would
    /// delete the old row first and fire referential delete actions.
    /// The price history is deliberately untouched: a backup carries its
    /// prices as their own entries, restored through [`Self::upsert_price`],
    /// so writing one here would compete with them.
    pub fn upsert_subscription(&self, sub: &Subscription) -> Result<bool> {
        let inserted = !self.exists("subscription", &sub.id.to_string())?;
        self.conn.execute(
            "INSERT INTO subscription (id, name, notes, template_id,
                 cycle_count, cycle_unit, first_billing_date, reminder_lead_days,
                 category_id, channel, account, payment_method_id,
                 status, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)
             ON CONFLICT(id) DO UPDATE SET
                 name = ?2, notes = ?3, template_id = ?4,
                 cycle_count = ?5, cycle_unit = ?6, first_billing_date = ?7,
                 reminder_lead_days = ?8, category_id = ?9, channel = ?10,
                 account = ?11, payment_method_id = ?12, status = ?13,
                 created_at = ?14, updated_at = ?15",
            params![
                sub.id.to_string(),
                sub.name,
                sub.notes,
                sub.template_id,
                sub.cycle.count(),
                unit_str(sub.cycle.unit()),
                sub.first_billing_date.to_string(),
                sub.reminder_lead_days,
                sub.category_id.map(|id| id.to_string()),
                Option::<String>::None,
                Option::<String>::None,
                Option::<String>::None,
                status_str(sub.status),
                sub.created_at.to_string(),
                sub.updated_at.to_string(),
            ],
        )?;
        Ok(inserted)
    }

    /// Deletes a subscription; returns whether a row existed.
    pub fn delete_subscription(&self, id: Uuid) -> Result<bool> {
        let changed = self
            .conn
            .execute("DELETE FROM subscription WHERE id = ?1", [id.to_string()])?;
        Ok(changed > 0)
    }

    /// Loads one subscription by id, priced as of `on`.
    ///
    /// `None` means no such subscription. A subscription that exists with
    /// no price at all is [`Error::Corrupt`] instead: it cannot be shown
    /// and it cannot be summed, and reporting it missing would hide the
    /// damage rather than surface it.
    pub fn subscription(&self, id: Uuid, on: Date) -> Result<Option<Subscription>> {
        let mut stmt = self
            .conn
            .prepare("SELECT * FROM subscription WHERE id = ?1")?;
        let mut rows = stmt.query([id.to_string()])?;
        let Some(row) = rows.next()? else {
            return Ok(None);
        };
        let history = self.price_history(id)?;
        let price = model::price_on(&history, on)
            .ok_or_else(|| Error::Corrupt(format!("subscription {id} has no price")))?;
        Ok(Some(subscription_from_row(row, price.amount.clone())?))
    }

    /// Lists subscriptions, optionally filtered by status, ordered by name,
    /// each priced as of `on`.
    ///
    /// Ordering by next billing date needs a reference day, so it belongs to
    /// the caller (via [`crate::cycle::next_billing_date`]), not to SQL.
    ///
    /// Prices are fetched in one query and matched up here rather than
    /// joined per row: the join that picks "the latest entry not after this
    /// day, or the earliest if none" reads as a puzzle in SQL and as three
    /// lines in Rust, and the whole history of every subscription is a few
    /// hundred rows.
    pub fn subscriptions(
        &self,
        status: Option<SubscriptionStatus>,
        on: Date,
    ) -> Result<Vec<Subscription>> {
        let histories = self.all_price_histories()?;
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
            let id = parse_uuid(row.get::<_, String>("id")?)?;
            let history = histories.get(&id).map(Vec::as_slice).unwrap_or_default();
            let price = model::price_on(history, on)
                .ok_or_else(|| Error::Corrupt(format!("subscription {id} has no price")))?;
            subs.push(subscription_from_row(row, price.amount.clone())?);
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

    /// Writes a category as given, inserting or overwriting by id.
    ///
    /// Returns whether the row was newly inserted. See
    /// [`Self::upsert_subscription`] for why this is not `INSERT OR REPLACE`:
    /// here it matters most, since replacing a category row would fire
    /// `ON DELETE SET NULL` and detach every subscription using it.
    pub fn upsert_category(&self, category: &Category) -> Result<bool> {
        let inserted = !self.exists("category", &category.id.to_string())?;
        self.conn.execute(
            "INSERT INTO category (id, name, sort_order) VALUES (?1, ?2, ?3)
             ON CONFLICT(id) DO UPDATE SET name = ?2, sort_order = ?3",
            params![category.id.to_string(), category.name, category.sort_order],
        )?;
        Ok(inserted)
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

/// How long a write waits for a competing lock before giving up.
///
/// Rondo writes from one connection, so contention only arises when another
/// process (a SQLite browser, a stray second instance) holds the lock. A few
/// seconds outlasts that; longer would just freeze the UI.
const BUSY_TIMEOUT: Duration = Duration::from_secs(5);

/// Applies the per-connection settings every Rondo database expects.
fn configure(conn: &Connection) -> Result<()> {
    // Foreign keys are per-connection in SQLite and off by default, so the
    // category reference would not be enforced without this.
    conn.pragma_update(None, "foreign_keys", "ON")?;
    conn.busy_timeout(BUSY_TIMEOUT)?;

    // WAL lets a reader work while a write is in flight, which keeps the UI
    // responsive; it is stored in the file, so this is a no-op after the
    // first open. In-memory databases do not support it and stay on their
    // own journal, hence the query form rather than a checked update.
    conn.query_row("PRAGMA journal_mode = WAL", [], |_| Ok(()))?;

    // NORMAL fsyncs at checkpoints rather than every commit. Under WAL that
    // risks losing the most recent commits to a power cut, never a corrupt
    // file - the right trade for subscription records the user can retype.
    conn.pragma_update(None, "synchronous", "NORMAL")?;
    Ok(())
}

/// The ordered schema migrations, applied on every open.
///
/// Each entry is immutable once released: a mistake is corrected by a new
/// migration, never by editing an old one, since databases that already ran
/// it would never see the edit.
static MIGRATIONS: LazyLock<Migrations<'static>> = LazyLock::new(|| {
    Migrations::new(vec![
        M::up(include_str!("../migrations/001-initial.sql")),
        M::up(include_str!("../migrations/002-price-history.sql")),
    ])
});

/// Rebuilds a [`Subscription`] from a row, re-validating every invariant.
///
/// The price arrives from the history rather than the row: it no longer
/// lives on the subscription, and which of its prices applies depends on
/// the day being asked about.
fn subscription_from_row(row: &Row<'_>, price: Money) -> Result<Subscription> {
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

/// Writes one price row.
///
/// Takes a `Connection` rather than a method on the store so it can run
/// inside a transaction that also writes the subscription, where the two
/// have to stand or fall together.
fn insert_price(conn: &Connection, price: &Price) -> Result<()> {
    conn.execute(
        "INSERT INTO subscription_price (id, subscription_id, effective_from,
             amount, currency, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![
            price.id.to_string(),
            price.subscription_id.to_string(),
            price.effective_from.to_string(),
            price.amount.amount().to_string(),
            price.amount.currency(),
            price.created_at.to_string(),
            price.updated_at.to_string(),
        ],
    )?;
    Ok(())
}

/// Rebuilds a [`Price`] from a row, re-validating the money invariant.
fn price_from_row(row: &Row<'_>) -> Result<Price> {
    Ok(Price {
        id: parse_uuid(row.get::<_, String>("id")?)?,
        subscription_id: parse_uuid(row.get::<_, String>("subscription_id")?)?,
        effective_from: parse_text(row.get::<_, String>("effective_from")?)?,
        amount: money_from_row(row)?,
        created_at: parse_text(row.get::<_, String>("created_at")?)?,
        updated_at: parse_text(row.get::<_, String>("updated_at")?)?,
    })
}

/// Reads the `amount` and `currency` columns of a price row as [`Money`].
fn money_from_row(row: &Row<'_>) -> Result<Money> {
    let amount: String = row.get("amount")?;
    let currency: String = row.get("currency")?;
    Money::new(
        amount
            .parse()
            .map_err(|e| Error::Corrupt(format!("amount {amount:?}: {e}")))?,
        &currency,
    )
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

    /// The day these tests read prices as of. Later than every sample's
    /// first charge, so the price in force is the one that was stored.
    const TODAY: Date = Date::constant(2026, 6, 1);

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
            SchemaVersion::Inside(NonZeroUsize::new(2).unwrap())
        );
    }

    /// The one test in this file that runs against a database built the way
    /// a released version built it. Everything else here starts at the
    /// current schema and so could never catch a migration that drops data.
    #[test]
    fn migrating_a_v1_database_carries_every_price_across() {
        let mut conn = Connection::open_in_memory().unwrap();
        configure(&conn).unwrap();
        let v1 = Migrations::new(vec![M::up(include_str!("../migrations/001-initial.sql"))]);
        v1.to_latest(&mut conn).unwrap();

        // Written through SQL rather than the store, because the store can
        // no longer produce a v1 row - which is the point.
        let rows = [
            ("Netflix", "15.99", "USD", "2026-01-31", "active"),
            ("网易云音乐", "8", "CNY", "2026-02-28", "active"),
            ("Retired", "100.50", "JPY", "2025-12-01", "archived"),
        ];
        for (name, amount, currency, first, status) in rows {
            let id = Uuid::now_v7().to_string();
            let now = Timestamp::now().to_string();
            conn.execute(
                "INSERT INTO subscription (id, name, notes, template_id, amount, currency,
                     cycle_count, cycle_unit, first_billing_date, reminder_lead_days,
                     category_id, status, created_at, updated_at)
                 VALUES (?1, ?2, NULL, NULL, ?3, ?4, 1, 'month', ?5, 3, NULL, ?6, ?7, ?7)",
                params![id, name, amount, currency, first, status, now],
            )
            .unwrap();
        }

        MIGRATIONS.to_latest(&mut conn).unwrap();
        let store = Store { conn };

        // Every subscription kept its price, exactly, and gained a history
        // of one entry starting at its first charge.
        let subs = store.subscriptions(None, TODAY).unwrap();
        assert_eq!(subs.len(), 3);
        for sub in &subs {
            let history = store.price_history(sub.id).unwrap();
            assert_eq!(history.len(), 1, "{} gained the wrong history", sub.name);
            assert_eq!(history[0].amount, sub.price);
            assert_eq!(history[0].effective_from, sub.first_billing_date);
        }

        let by_name = |name: &str| {
            subs.iter()
                .find(|s| s.name == name)
                .unwrap_or_else(|| panic!("{name} disappeared"))
                .clone()
        };
        // The exact strings, not parsed and reprinted: "8" must not become
        // "8.00", and 15.99 must not become 15.989999999999998.
        assert_eq!(by_name("Netflix").price.amount().to_string(), "15.99");
        assert_eq!(by_name("网易云音乐").price.amount().to_string(), "8");
        assert_eq!(by_name("网易云音乐").price.currency(), "CNY");
        assert_eq!(
            by_name("Retired").status,
            SubscriptionStatus::Archived,
            "an archived subscription must survive the migration as archived"
        );

        // The new columns exist and say nothing yet, which is the honest
        // answer for rows written before they did.
        assert!(by_name("Netflix").notes.is_none());
        let channel: Option<String> = store
            .conn
            .query_row("SELECT channel FROM subscription LIMIT 1", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert!(channel.is_none());
    }

    /// A subscription whose first charge has not arrived yet still has a
    /// price - the one it will be charged at. This is the shape of every
    /// row in a database whose owner adds subscriptions before they start.
    #[test]
    fn a_price_starting_later_than_today_is_still_the_price() {
        let store = Store::open_in_memory().unwrap();
        let mut sub = sample();
        sub.first_billing_date = Date::constant(2027, 3, 20);
        store.insert_subscription(&sub).unwrap();

        let loaded = store.subscription(sub.id, TODAY).unwrap().unwrap();
        assert_eq!(loaded.price, sub.price);
    }

    #[test]
    fn a_rise_leaves_earlier_days_at_the_earlier_price() {
        let store = Store::open_in_memory().unwrap();
        let sub = sample();
        store.insert_subscription(&sub).unwrap();
        let risen = Money::new(Decimal::from_str("19.99").unwrap(), "USD").unwrap();
        store
            .add_price_change(sub.id, risen.clone(), Date::constant(2026, 4, 1))
            .unwrap();

        let before = store
            .subscription(sub.id, Date::constant(2026, 3, 31))
            .unwrap()
            .unwrap();
        assert_eq!(before.price.amount().to_string(), "15.99");
        let on_the_day = store
            .subscription(sub.id, Date::constant(2026, 4, 1))
            .unwrap()
            .unwrap();
        assert_eq!(on_the_day.price, risen);
        assert_eq!(store.price_history(sub.id).unwrap().len(), 2);
    }

    /// Editing a subscription's price is a correction, so it must not leave
    /// a second entry behind claiming the price changed.
    #[test]
    fn editing_a_price_corrects_it_rather_than_recording_a_rise() {
        let store = Store::open_in_memory().unwrap();
        let mut sub = sample();
        store.insert_subscription(&sub).unwrap();

        sub.price = Money::new(Decimal::from_str("17.99").unwrap(), "USD").unwrap();
        store.update_subscription(&sub, TODAY).unwrap();

        let history = store.price_history(sub.id).unwrap();
        assert_eq!(history.len(), 1, "a correction is not a price change");
        assert_eq!(history[0].amount.amount().to_string(), "17.99");
    }

    /// A correction applies to the entry that was in force, not to the
    /// latest one: fixing this month's price must not rewrite last year's.
    #[test]
    fn a_correction_lands_on_the_entry_in_force_that_day() {
        let store = Store::open_in_memory().unwrap();
        let mut sub = sample();
        store.insert_subscription(&sub).unwrap();
        store
            .add_price_change(
                sub.id,
                Money::new(Decimal::from_str("19.99").unwrap(), "USD").unwrap(),
                Date::constant(2026, 4, 1),
            )
            .unwrap();

        sub.price = Money::new(Decimal::from_str("16.99").unwrap(), "USD").unwrap();
        store
            .update_subscription(&sub, Date::constant(2026, 2, 1))
            .unwrap();

        let history = store.price_history(sub.id).unwrap();
        assert_eq!(history.len(), 2);
        assert_eq!(history[0].amount.amount().to_string(), "16.99");
        assert_eq!(history[1].amount.amount().to_string(), "19.99");
    }

    #[test]
    fn the_last_price_cannot_be_deleted() {
        let store = Store::open_in_memory().unwrap();
        let sub = sample();
        store.insert_subscription(&sub).unwrap();
        let only = store.price_history(sub.id).unwrap()[0].id;
        assert!(store.delete_price(only).is_err());

        let second = store
            .add_price_change(
                sub.id,
                Money::new(Decimal::from_str("19.99").unwrap(), "USD").unwrap(),
                Date::constant(2026, 4, 1),
            )
            .unwrap();
        assert!(store.delete_price(second.id).unwrap());
        assert!(!store.delete_price(Uuid::now_v7()).unwrap());
    }

    #[test]
    fn deleting_a_subscription_takes_its_prices_with_it() {
        let store = Store::open_in_memory().unwrap();
        let sub = sample();
        store.insert_subscription(&sub).unwrap();
        assert!(store.delete_subscription(sub.id).unwrap());
        assert!(store.price_history(sub.id).unwrap().is_empty());
    }

    #[test]
    fn two_prices_cannot_start_on_the_same_day() {
        let store = Store::open_in_memory().unwrap();
        let sub = sample();
        store.insert_subscription(&sub).unwrap();
        assert!(
            store
                .add_price_change(sub.id, sub.price.clone(), sub.first_billing_date)
                .is_err()
        );
    }

    #[test]
    fn subscription_round_trips_exactly() {
        let store = Store::open_in_memory().unwrap();
        let mut sub = sample();
        sub.notes = Some("family plan".into());
        store.insert_subscription(&sub).unwrap();
        assert_eq!(store.subscription(sub.id, TODAY).unwrap().unwrap(), sub);
        assert!(store.subscription(Uuid::now_v7(), TODAY).unwrap().is_none());
    }

    #[test]
    fn update_refreshes_updated_at_and_persists() {
        let store = Store::open_in_memory().unwrap();
        let mut sub = sample();
        store.insert_subscription(&sub).unwrap();
        sub.name = "Netflix Premium".into();
        let stored = store.update_subscription(&sub, TODAY).unwrap();
        assert!(stored.updated_at >= sub.updated_at);
        assert_eq!(store.subscription(sub.id, TODAY).unwrap().unwrap(), stored);
        // Updating a missing row is corruption, not silence.
        assert!(store.update_subscription(&sample(), TODAY).is_err());
    }

    #[test]
    fn upsert_reports_insertion_and_keeps_timestamps_verbatim() {
        let store = Store::open_in_memory().unwrap();
        let mut sub = sample();
        assert!(store.upsert_subscription(&sub).unwrap());
        // Upserting writes no price, the way restoring a backup does not:
        // the file's own price entries follow, and here one stands in for
        // them.
        store
            .upsert_price(&Price::new(
                sub.id,
                sub.price.clone(),
                sub.first_billing_date,
            ))
            .unwrap();

        sub.name = "Renamed".into();
        assert!(!store.upsert_subscription(&sub).unwrap());
        let stored = store.subscription(sub.id, TODAY).unwrap().unwrap();
        assert_eq!(stored, sub);
        // A restore must not rewrite history the way update_subscription does.
        assert_eq!(stored.updated_at, sub.updated_at);
    }

    #[test]
    fn upserting_a_category_keeps_its_subscriptions_attached() {
        let store = Store::open_in_memory().unwrap();
        let mut category = Category::new("Streaming", 0).unwrap();
        store.insert_category(&category).unwrap();
        let mut sub = sample();
        sub.category_id = Some(category.id);
        store.insert_subscription(&sub).unwrap();

        category.name = "Video".into();
        assert!(!store.upsert_category(&category).unwrap());
        // INSERT OR REPLACE would have deleted the row first and fired
        // ON DELETE SET NULL, silently detaching this subscription.
        let reloaded = store.subscription(sub.id, TODAY).unwrap().unwrap();
        assert_eq!(reloaded.category_id, Some(category.id));
        assert_eq!(store.categories().unwrap(), vec![category]);
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
            .subscriptions(Some(SubscriptionStatus::Active), TODAY)
            .unwrap();
        assert_eq!(
            active.iter().map(|s| s.name.as_str()).collect::<Vec<_>>(),
            vec!["Alpha", "beta"]
        );
        assert_eq!(store.subscriptions(None, TODAY).unwrap().len(), 3);
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
        let reloaded = store.subscription(sub.id, TODAY).unwrap().unwrap();
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
    fn file_databases_use_wal_and_enforce_foreign_keys() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::open(&dir.path().join("rondo.sqlite3")).unwrap();

        let mode: String = store
            .conn
            .query_row("PRAGMA journal_mode", [], |r| r.get(0))
            .unwrap();
        assert_eq!(mode, "wal");
        let foreign_keys: i64 = store
            .conn
            .query_row("PRAGMA foreign_keys", [], |r| r.get(0))
            .unwrap();
        assert_eq!(foreign_keys, 1);
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
        assert_eq!(store.subscription(sub.id, TODAY).unwrap().unwrap(), sub);
    }
}
