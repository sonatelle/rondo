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
|    records - errors - the Rondo object frontends hold   |
+---------------------------↓-----------------------------+
|  crates/rondo-core  all business logic                  |
|    domain model - cycle math - summaries - templates    |
|    SQLite storage - versioned JSON backup               |
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

## The language boundary

`rondo-ffi` translates and nothing more. It holds no rules of its own, so
that everything worth testing stays in `rondo-core` where a test needs no
foreign runtime.

Values cross as their canonical string form - the same text the database
and the backup file already hold, so one representation serves every layer:

| Core type | Crosses as | Named on the far side |
| --- | --- | --- |
| `Decimal` | exact decimal text | `DecimalString` |
| `civil::Date` | `YYYY-MM-DD` | `CivilDate` |
| `Timestamp` | RFC 3339 | `Timestamp` |
| `Uuid` | hyphenated form | `Uuid` |

Money must never cross as a double. 15.99 has no exact binary fraction, so
the amount would arrive quietly wrong and no test on either side would
notice. `Decimal` and `Date` are renamed in `crates/rondo-ffi/uniffi.toml`
because Swift declares one type per Rust type name, and bare `Date` would
then be ambiguous against `Foundation.Date` at every use site. Renaming
there rather than wrapping them in Rust keeps the core types intact on
this side of the boundary.

`Money` and `BillingCycle` are flattened into their parts on the way out,
since a record's fields must be public and those types keep theirs private.
Rebuilding one goes back through the validating constructors, so a frontend
cannot assemble a subscription the core would have refused.

The seven core failure kinds collapse into three - `InvalidInput`,
`Storage`, `UnusableData` - because a user interface only has three
responses: point at the field, report the database, or say the data is
unusable and offer a backup. The detail rides along in `message`.

## Dependency choices

The core is small, but it sits behind an FFI boundary and defines a
persistence format. That makes a dependency's API stability worth more
than its benchmark numbers: a breaking change in any of these types
propagates into the SQLite schema, the backup format, and the Swift side
at once. The alternatives below were compared in August 2026; each was
rejected for a concrete reason, not by default.

| Job | Chosen | Considered and why not |
| --- | --- | --- |
| Storage | `rusqlite` | `redb` is a key-value store with no queries, foreign keys, or migrations. `native_db` has not released since July 2025. `turso` is beta and async-first. `sqlx` keeps the C dependency *and* forces an async runtime. |
| JSON | `serde_json` | `sonic-rs` needs `-C target-cpu=native`, which cannot produce a universal or cross-compiled binary. `simd-json` parses destructively, so a read-only backup must be copied first. |
| Decimal | `rust_decimal` | `fastnum` is pre-1.0 and states its API may break. `bigdecimal` is arbitrary-precision and heap-allocating, which money is not. |
| Ids | `uuid` (v7) | `ulid` shipped two breaking majors in one week of July 2026, and Swift's Foundation has `UUID` but no ULID. |
| Dates | `jiff` | `chrono` and `time` lack the calendar arithmetic that makes month-end billing correct. |

Two consequences worth stating plainly. First, the SIMD JSON parsers would
save well under a millisecond on a backup file of this size - far less than
one frame of UI - in exchange for cross-compilation risk on iOS. Second,
SQLite's C dependency is not a portability problem: compiling the bundled
amalgamation for iOS and Android is a long-established path, and Rondo
already needs those toolchains for UniFFI.

Revisit the storage choice if `turso` reaches 1.0 with a synchronous API,
or if a target platform appears that has no C toolchain.

## Crate layout

- `crates/rondo-core` - domain model (`model`), occurrence math (`cycle`),
  spending summaries (`summary`), bundled service templates (`templates`),
  SQLite persistence (`store`), JSON backup (`backup`), structured errors
  (`error`).
- `crates/rondo-core/migrations/` - schema migrations, applied on open and
  tracked in `PRAGMA user_version`. A released migration is never edited;
  a mistake is corrected by adding another one.
- `crates/rondo-ffi` - UniFFI layer, kept free of logic: the records that
  cross (`records`), the boundary value types (`types`), the failures
  (`error`), and `Rondo`, the object a frontend opens and calls.
- `scripts/` - `build-xcframework.sh` packages the core for Xcode;
  `swift-smoke-test.sh` proves the packaged result actually runs.
- `apple/smoke/` - the Swift program that smoke test compiles and runs.
- `apple/RondoCore/` - the packaged XCFramework and generated Swift. Build
  output, not source; it is not in version control.
- `crates/rondo-core/templates/services.json` - service catalogue compiled
  into the core.
