# Roadmap

Status as of August 2026. Milestones land in order; each one is usable on
its own before the next begins.

## M1 - Core foundation (done)

- [x] Cargo workspace, CI on Ubuntu and macOS
- [x] Domain model: subscriptions, categories, money, billing cycles
- [x] Anchored billing-cycle math with month-end clamping
- [x] Per-currency spending summaries (monthly / yearly)
- [x] Bundled service templates
- [x] SQLite storage with migrations
- [x] JSON backup export and import

## M2 - FFI bridge (done)

- [x] UniFFI bindings in `rondo-ffi`
- [x] `RondoCore.xcframework` build script
- [x] Swift smoke test against the bridge

## M3 - macOS app (done, first usable release)

- [x] Subscription list sorted by next billing date
- [x] Add / edit form with template picker
- [x] Monthly spending summary header
- [x] Archive, restore, and delete

## M4 - Reminders and polish (in progress)

- [x] A window shaped like a macOS app: sidebar, sortable table, menus
- [x] A menu bar item showing what is charged next
- [x] Settings, including a way to reach the data file
- [x] Backup export and restore from the app
- [x] An app icon
- [x] A currency picker, in place of typing the code in
- [ ] Local notifications ahead of renewals
- [ ] A visual pass; the shape is right but it is still plain

## M5 - Release

- [x] dmg packaging, drafted by pushing a version tag and published by hand
- [x] Known limitation recorded: without notarization the first launch
      needs right-click -> Open past Gatekeeper
- [x] v0.1.0 published, 2026-08-28

## Later, undated

- iOS delivery (blocked on a distribution story outside GitHub Releases)
- Windows / Linux / Android frontends against the same core
- Device sync (the data model already reserves ids and timestamps)

## Non-goals for the MVP

Currency conversion, tags, charts, widgets, accounts, and App Store
integrations are deliberately out of scope until the MVP is done.
