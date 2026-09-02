# Rondo Agent Guide

Rondo is a subscription tracker built as a shared Rust core with native
platform interfaces. This guide records the architecture rules and
conventions for working in this repository. It refines the Sonatelle
organization conventions; where the two differ, this file wins here.

## Architecture

- `crates/rondo-core` owns all business logic: domain model, billing-cycle
  math, statistics, SQLite storage, and JSON import/export. It has no UI,
  no network, and no platform-specific code.
- `crates/rondo-ffi` is a thin UniFFI layer over `rondo-core`. It adapts
  types to the UniFFI-supported subset and adds nothing else. A rule that
  belongs in a test belongs in the core, not here.
- Values cross the boundary as their canonical string form. Money crosses
  as text and never as a double: 15.99 has no exact binary fraction, so it
  would arrive quietly wrong with nothing to catch it.
- A frontend rebuilds core entities through the validating constructors,
  so it can never assemble something the core would have refused.
- After changing `rondo-ffi`, run `scripts/build-xcframework.sh` and then
  `scripts/swift-smoke-test.sh`. The Rust tests never link the packaged
  artifact, so they cannot see a package that builds but cannot be used.
- `apple/` holds the SwiftUI application. macOS is the delivery target;
  keep views reusable for iOS (no AppKit-only APIs without need).
- UI layers stay thin. If a rule about subscriptions, money, or dates is
  worth testing, it belongs in `rondo-core`, not in Swift.
- New platforms get their own thin UI against the same core; do not fork
  business logic per platform.
- Frontend directories are named for the ecosystem that builds them, never
  for the platform they run on: `apple/` ships both macOS and iOS, and two
  frontends may one day target the same platform. A Rust frontend belongs
  in `crates/` and uses `rondo-core` directly; only other languages need
  `rondo-ffi`.
- Data a crate compiles in lives inside that crate, not at the repository
  root.

## Domain Rules

- Money is `rust_decimal::Decimal`, never a float. Persist amounts as
  TEXT; round only at presentation time.
- A subscription has a price *history*, not a price. `Subscription::price`
  is the entry in force on the day it was loaded for, which is why loading
  one takes a date. Anything summing charges over time walks
  `Store::price_history` instead; a total built by multiplying the current
  price is wrong by every rise that ever happened.
- Editing a subscription's price **corrects** the entry in force;
  `add_price_change` records a rise. Which of the two happened is the
  person's to say and must never be guessed from the numbers.
- Billing dates are civil dates (`jiff::civil::Date`) with no time zone.
- Billing occurrences are anchored to `first_billing_date`: occurrence *k*
  is `first + k * cycle`, with month-end clamping (Jan 31 + 1 month =
  Feb 28/29). Never derive the next date from the previous computed date,
  or short months make the schedule drift.
- Entity ids are UUIDv7 (`Uuid::now_v7`), so they sort in creation order;
  rows carry `created_at` / `updated_at` UTC timestamps. These exist to
  make future device sync possible - keep them correct even though nothing
  syncs yet.
- Schema changes are new migrations under `crates/rondo-core/migrations/`.
  An already-released migration is immutable: databases that ran it would
  never see the edit.
- Restoring data must preserve stored timestamps: use the `upsert_*` store
  methods, not `update_*`, which deliberately refresh `updated_at`.
- The backup format is versioned. Any change an older build could not read
  correctly needs `backup::FORMAT_VERSION` raised and a migration path for
  the old shape; import must keep refusing versions from the future.
- Importing a backup merges and never deletes, so restoring the wrong file
  cannot destroy data. Keep it that way.
- Data is local-only. `rondo-core` must not perform network requests.

## Development Environment

- The dev shell comes from nix-direnv (`.envrc` + `flake.nix`, based on
  the Sonatelle Prelude module). In non-interactive shells run tools as
  `direnv exec . cargo <cmd>`.
- Before committing Rust changes, run and pass:
  `cargo fmt --check`, `cargo clippy --workspace -- -D warnings`,
  `cargo test --workspace`.
- Scaffold with native tooling (`cargo new`, `cargo add`), then edit.

## Git Workflow

- All work lands through pull requests, even solo. Use one short-lived
  branch per independent change; `main` stays stable.
- Use Conventional Commits subjects (e.g. `feat(core): add cycle math`).
- Commit in small, single-intent increments; each commit should build and
  pass checks on its own.
- Land each unit as soon as it stands alone and passes checks, before
  starting the next one. Do not write a whole feature across many files
  and split it into commits afterwards: retroactively split commits were
  never built or tested individually, so one of them can silently fail to
  compile and history stops being bisectable.
- To keep a not-yet-landed module out of a commit, leave it undeclared in
  `lib.rs` (an undeclared file is not compiled); declare it in the same
  commit that adds the file, and run the full checks at each commit's own
  tree state.
- Show proposed commit messages to the user and wait for approval before
  committing.
- Merge with GitHub `Rebase and merge` by default; delete branches after
  merge.

## Comments And Documentation

Follow the Sonatelle comment standard: explain intent, constraints, and
invariants rather than restating code; give every public API item a doc
comment; open each module with a one-line responsibility statement; write
comments in English. Public claims in README and docs must come from
implemented behavior.

## MVP Non-Goals

Do not add these without an explicit decision: currency conversion, tags,
charts, widgets, device sync, accounts, or any App Store-specific
integration (IAP, iCloud entitlements).
