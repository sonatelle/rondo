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

## M2 - FFI bridge (next)

- [ ] UniFFI bindings in `rondo-ffi`
- [ ] `RondoCore.xcframework` build script
- [ ] Swift smoke test against the bridge

## M3 - macOS app (first usable release)

- [ ] Subscription list sorted by next billing date
- [ ] Add / edit form with template picker
- [ ] Monthly spending summary header

## M4 - Reminders and polish

- [ ] Local notifications ahead of renewals
- [ ] Archive view, settings, import/export UI

## M5 - Release

- [ ] dmg packaging, GitHub Releases
- [ ] Known limitation: without notarization the first launch needs
      right-click -> Open past Gatekeeper

## Later, undated

- iOS delivery (blocked on a distribution story outside GitHub Releases)
- Windows / Linux / Android frontends against the same core
- Device sync (the data model already reserves ids and timestamps)

## Non-goals for the MVP

Currency conversion, tags, charts, widgets, accounts, and App Store
integrations are deliberately out of scope until the MVP is done.
