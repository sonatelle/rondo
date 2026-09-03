-- The categories every database starts with.
--
-- They exist so that picking a category is choosing from a list rather than
-- inventing one, and so the sidebar has something in it before anybody has
-- filed anything. They are ordinary rows: rename them, reorder them, delete
-- the ones you have no use for.
--
-- The ids are fixed rather than generated. A built-in category is the same
-- category on every machine, so two devices that ever sync should agree it
-- is one row and not two, and a backup taken on one restores onto the other
-- without doubling them. They are shaped like a UUIDv7 with a zero
-- timestamp, which sorts them ahead of anything created since.
--
-- Names are English, and a frontend showing one that still reads as it does
-- here may translate it. Once somebody renames a category the stored name is
-- theirs and no frontend second-guesses it. Storing a translated name
-- instead would freeze whichever language happened to be on at the moment
-- the database was created.
--
-- `icon_key` matches the `default_category` a bundled service template
-- carries, which is how picking Netflix knows to file it under Video.

INSERT INTO category (id, name, sort_order, icon_key, color_key) VALUES
    ('00000000-0000-7000-8000-000000000001', 'Video',   1, 'video',   'pink'),
    ('00000000-0000-7000-8000-000000000002', 'Music',   2, 'music',   'violet'),
    ('00000000-0000-7000-8000-000000000003', 'Reading', 3, 'reading', 'green'),
    ('00000000-0000-7000-8000-000000000004', 'Games',   4, 'games',   'red'),
    ('00000000-0000-7000-8000-000000000005', 'Tools',   5, 'tools',   'amber'),
    ('00000000-0000-7000-8000-000000000006', 'AI',      6, 'ai',      'teal'),
    ('00000000-0000-7000-8000-000000000007', 'Dev',     7, 'dev',     'blue'),
    ('00000000-0000-7000-8000-000000000008', 'Storage', 8, 'storage', 'cyan');
