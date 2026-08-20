# Architecture

Rondo is built as one shared Rust core with a thin native interface per
platform. The core owns every business rule; each frontend only renders
state and forwards user intent.

```text
+---------------------------------------------------------+
|  Frontends (thin, per platform)                         |
|    apple/        SwiftUI - macOS now, iOS later         |
|    (future)      Windows / Linux / Android              |
+---------------------------↓-----------------------------+
|  crates/rondo-ffi   UniFFI bindings                     |
|    adapts the core API to the UniFFI type subset        |
+---------------------------↓-----------------------------+
|  crates/rondo-core  all business logic                  |
|    domain model - cycle math - summaries - templates    |
|    SQLite storage - JSON backup (planned)               |
+---------------------------------------------------------+
```

## Why this shape

Subscription logic is where the bugs that matter live: date arithmetic,
money precision, schedule drift. Keeping it in one tested Rust crate means
every platform shares the same behavior, and a new platform costs only a
new thin UI. The trade-off is an FFI boundary and a mixed Cargo/Xcode
build, paid once in `rondo-ffi` and the build scripts.

## Domain rules

These invariants hold everywhere in the codebase:

- **Money is exact.** Amounts are `rust_decimal::Decimal`, never floating
  point. Persisted as text; rounded only for display. Currencies are kept
  separate - Rondo does not convert between them.
- **Billing dates are civil dates.** A renewal happens on a calendar date
  (`jiff::civil::Date`), not at an instant in a time zone.
- **Occurrences are anchored.** Occurrence *k* of a schedule is
  `first_billing_date + k x cycle`, always computed from the anchor date.
  Month-end dates clamp (Jan 31 + 1 month = Feb 28/29) but never drift:
  Jan 31 -> Feb 28 -> Mar 31, not Mar 28.
- **Normalization convention.** For summaries, a year is 365.25 days and a
  month is exactly 1/12 of a year. Month- and year-based cycles divide
  exactly; day- and week-based cycles are approximations by nature.
- **Local-only data.** The core performs no network requests. Entities
  carry UUIDv7 ids and UTC created/updated timestamps so a future sync
  feature remains possible, but nothing syncs today. A v7 id embeds its
  creation millisecond, so ids sort in creation order - inserts stay local
  in the index, and a sync can page through changes by id.
- **Stored values re-enter through the constructors.** Rows are text in
  canonical form and every read rebuilds the entity with the validating
  constructors, so a database edited outside Rondo fails loudly rather
  than loading invalid state.

## Crate layout

- `crates/rondo-core` - domain model (`model`), occurrence math (`cycle`),
  spending summaries (`summary`), bundled service templates (`templates`),
  SQLite persistence (`store`), structured errors (`error`). JSON backup
  lands next.
- `crates/rondo-core/migrations/` - schema migrations, applied on open and
  tracked in `PRAGMA user_version`. A released migration is never edited;
  a mistake is corrected by adding another one.
- `crates/rondo-ffi` - UniFFI layer, kept free of logic.
- `templates/services.json` - service catalogue compiled into the core.
