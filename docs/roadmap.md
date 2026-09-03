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
- [ ] Local notifications ahead of renewals - now part of M6
- [ ] A visual pass - grew into M6

## M5 - Release

- [x] dmg packaging, drafted by pushing a version tag and published by hand
- [x] Known limitation recorded: without notarization the first launch
      needs right-click -> Open past Gatekeeper
- [x] v0.1.0 published, 2026-08-28
- [x] v0.2.0 published, 2026-09-01
- [x] v0.3.0 published, 2026-09-03 - the release the backup format moved in

## M6 - The design handoff (in progress)

Eleven screens, delivered as a hifi design in August 2026. It is named a
milestone of its own because it is not a coat of paint: six of the screens
do not exist, the overview is a rewrite rather than a restyle, and the
handoff asks the core for price history, payment methods and a provider
table. One round per pull request, in dependency order; the version each
round ships in is named, because one of them changes the backup format and
that needs a boundary a reader can point at.

- [x] Design tokens, the menu bar window, the settings shell - v0.2.0
- [x] A bilingual interface with a language of its own to pick - v0.2.0
- [x] A provider table, with aliases to search by - v0.3.0
- [x] Price history, payment methods, category icons - one migration, and
      the backup format to v2 - v0.3.0
- [x] The aggregations the analytics screen needs - v0.3.0
- [ ] Sidebar navigation and the overview - v0.4.0
- [ ] The form, and picking a provider - v0.4.0
- [ ] Subscription detail - v0.5.0
- [ ] Calendar - v0.5.0
- [ ] Analytics - v0.6.0
- [ ] First run - v0.7.0
- [ ] Local notifications - which also closes M4 - v0.7.0

v0.3.0 was the release to be careful with. Its screens barely changed, but
a backup written after it cannot be read by v0.1.0 or v0.2.0, which refuse
formats from the future by design.

## Later, undated

- iOS delivery (blocked on a distribution story outside GitHub Releases)
- Windows / Linux / Android frontends against the same core
- Device sync (the data model already reserves ids and timestamps)

## Non-goals for the MVP

Currency conversion, tags, charts, widgets, accounts, and App Store
integrations are deliberately out of scope until the MVP is done.
