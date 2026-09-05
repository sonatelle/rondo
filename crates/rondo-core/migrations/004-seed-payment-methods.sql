-- The ways of paying every database starts with.
--
-- The same reasoning as the categories in 003: picking one should be
-- choosing from a list rather than inventing a name, and the picker in the
-- form has nothing to offer on a database nobody has filled in yet. They
-- are ordinary rows - rename them, or delete the ones you never pay with.
--
-- The ids are fixed, so a built-in is the same row on every machine and a
-- backup taken on one restores onto the other without doubling them. They
-- are shaped like a UUIDv7 with a zero timestamp, which sorts them ahead of
-- anything created since, and they are numbered from 0x101 to keep them
-- apart from the categories at a glance in an exported backup.
--
-- Names are English and a frontend may translate one that still reads as it
-- does here; the moment somebody renames it their name is the answer. The
-- timestamps are the epoch rather than the moment the migration ran: these
-- rows were not created by anybody, and a sync that ever compares them
-- should see every machine's copy as equally old.
--
-- What a payment method holds is a name and nothing else. There is no card
-- number here and there will not be one: Rondo is a list of what renews,
-- not a wallet.

INSERT INTO payment_method (id, name, sort_order, created_at, updated_at) VALUES
    ('00000000-0000-7000-8000-000000000101', 'Gift card', 1,
     '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z'),
    ('00000000-0000-7000-8000-000000000102', 'WeChat',    2,
     '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z'),
    ('00000000-0000-7000-8000-000000000103', 'Alipay',    3,
     '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z'),
    ('00000000-0000-7000-8000-000000000104', 'Bank card', 4,
     '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z');
