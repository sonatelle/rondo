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
  types to the UniFFI-supported subset and adds nothing else.
- `apple/` holds the SwiftUI application. macOS is the delivery target;
  keep views reusable for iOS (no AppKit-only APIs without need).
- UI layers stay thin. If a rule about subscriptions, money, or dates is
  worth testing, it belongs in `rondo-core`, not in Swift.
- New platforms (Windows, Linux, Android) get their own thin UI against
  the same core; do not fork business logic per platform.

## Domain Rules

- Money is `rust_decimal::Decimal`, never a float. Persist amounts as
  TEXT; round only at presentation time.
- Billing dates are civil dates (`jiff::civil::Date`) with no time zone.
- Billing occurrences are anchored to `first_billing_date`: occurrence *k*
  is `first + k * cycle`, with month-end clamping (Jan 31 + 1 month =
  Feb 28/29). Never derive the next date from the previous computed date,
  or short months make the schedule drift.
- Entity ids are UUIDv4; rows carry `created_at` / `updated_at` UTC
  timestamps. These exist to make future device sync possible - keep them
  correct even though nothing syncs yet.
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
