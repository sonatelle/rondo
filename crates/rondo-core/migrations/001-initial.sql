-- Initial schema: categories and the subscriptions that reference them.
--
-- STRICT keeps SQLite from silently coercing column types. Amounts, dates,
-- and timestamps are TEXT in canonical string form (exact decimal, ISO
-- date, RFC 3339 UTC) so the file stays readable and exact.
--
-- Applied migrations are immutable: fix a mistake with a new migration,
-- never by editing this file, or existing databases will not get the fix.

CREATE TABLE category (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    sort_order INTEGER NOT NULL
) STRICT;

CREATE TABLE subscription (
    id                 TEXT PRIMARY KEY,
    name               TEXT NOT NULL,
    notes              TEXT,
    template_id        TEXT,
    amount             TEXT NOT NULL,
    currency           TEXT NOT NULL,
    cycle_count        INTEGER NOT NULL,
    cycle_unit         TEXT NOT NULL,
    first_billing_date TEXT NOT NULL,
    reminder_lead_days INTEGER NOT NULL,
    category_id        TEXT REFERENCES category(id) ON DELETE SET NULL,
    status             TEXT NOT NULL,
    created_at         TEXT NOT NULL,
    updated_at         TEXT NOT NULL
) STRICT;

CREATE INDEX subscription_by_status ON subscription(status);
