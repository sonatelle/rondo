-- Price history, payment details, and category appearance.
--
-- Three changes in one migration on purpose. Each is an ALTER or a new
-- table, and splitting them would mean two backup formats to migrate
-- between rather than one.
--
-- The price stops living on the subscription. A subscription that has been
-- charged for two years at two different prices has two answers to "what
-- does it cost", and a single column can only hold one of them, so every
-- cumulative total computed from it is wrong by the difference. The table
-- below is the only place a price is stored from here on; the amount and
-- currency columns are dropped once their values have been carried across.

CREATE TABLE subscription_price (
    id              TEXT PRIMARY KEY,
    subscription_id TEXT NOT NULL REFERENCES subscription(id) ON DELETE CASCADE,
    -- The civil date this price took effect. Charges on or after it, and
    -- before the next entry's date, are at this amount.
    effective_from  TEXT NOT NULL,
    amount          TEXT NOT NULL,
    currency        TEXT NOT NULL,
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL
) STRICT;

-- No two prices may take effect on the same day for one subscription:
-- which of them applied would be unanswerable. Being an index as well as a
-- constraint, it also serves the only lookup there is - one subscription's
-- prices, in date order.
CREATE UNIQUE INDEX subscription_price_one_per_day
    ON subscription_price(subscription_id, effective_from);

-- Carry every existing price across as the one entry there has ever been,
-- effective from the first charge. That is the earliest date the price can
-- be known to have applied, and it makes every occurrence fall inside a
-- priced span rather than before the first one.
--
-- The id is derived from the subscription's own, keeping this migration
-- deterministic: two devices running it over the same data produce the
-- same rows, which matters if these ever sync.
INSERT INTO subscription_price (
    id, subscription_id, effective_from, amount, currency, created_at, updated_at
)
SELECT
    id, id, first_billing_date, amount, currency, created_at, updated_at
FROM subscription;

ALTER TABLE subscription DROP COLUMN amount;
ALTER TABLE subscription DROP COLUMN currency;

-- How a subscription is paid for, which the notes field was carrying by
-- hand until now.
--
-- A payment method is a row rather than free text so that renaming one
-- renames it everywhere, and so a future screen can group by it.
CREATE TABLE payment_method (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    sort_order INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
) STRICT;

-- Where the subscription was bought: 'app_store', 'google_play', 'web' or
-- 'other'. Null means nobody has said, which is every row that predates
-- this migration - deliberately not defaulted to 'other', so "unknown" and
-- "known to be something else" stay apart.
ALTER TABLE subscription ADD COLUMN channel TEXT;

-- The account it is billed to, as the person writes it: an email address,
-- a phone number, a family-plan owner's name.
ALTER TABLE subscription ADD COLUMN account TEXT;

ALTER TABLE subscription ADD COLUMN payment_method_id TEXT
    REFERENCES payment_method(id) ON DELETE SET NULL;

-- What a category looks like, as semantic keys rather than symbol names or
-- hex: the core is shared, and each frontend maps a key to its own icons
-- and palette. Null means the frontend picks, which is every existing row.
ALTER TABLE category ADD COLUMN icon_key TEXT;
ALTER TABLE category ADD COLUMN color_key TEXT;
