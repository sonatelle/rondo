# Rondo

A theme that keeps returning.

Rondo takes its name from the *rondo*, a form in which the main theme
comes back again and again between contrasting episodes. That temperament
fits this project: subscriptions return on their own schedule, and Rondo
keeps track of each return.

Rondo is a subscription tracker. A shared Rust core holds the data model,
billing-cycle math, storage, and import/export; each platform gets its own
native interface, starting with a SwiftUI app for macOS.

## Status

v0.3.0 is out. The macOS app runs and keeps real data.

**Backups written by v0.3.0 cannot be read by v0.1.0 or v0.2.0.** They
carry a price history those builds know nothing about, and a build refuses
a format newer than its own by design. Backups written by the older builds
restore here as they always did.

What works:

- Record subscriptions with a price, a billing cycle, and a first charge,
  starting from a bundled service or from nothing.
- See what renews next, and what it all costs per month, per currency.
- Edit, archive, restore, and delete.
- Glance at the next charges from the menu bar without opening a window.
- Export a backup, and restore one. Restoring merges and never deletes, so
  opening the wrong file cannot cost you data.
- Record a price in any currency the system knows, picked from a list.
  Currencies are kept apart; Rondo never converts between them.
- Read it in English or Simplified Chinese, chosen in Settings rather than
  inherited from the system. Dates and amounts follow the language picked.
- Light, dark, or follow the system, the menu bar item included.
- Local SQLite storage. No cloud, no account, no network.

v0.3.0 changes almost nothing you can see. It is the release where the
data model learned price history, payment methods and category icons, so
that the screens still to come can be right about what things cost. The
screens that use it arrive in v0.4.0 and v0.5.0.

Still to come:

- Renewal reminders through local notifications.
- The rest of the design. The menu bar and settings carry it; the main
  window, and the six screens that do not exist yet, do not.

## Install

[Download the latest release](https://github.com/sonatelle/rondo/releases/latest),
open the disk image, and drag Rondo to Applications.

Rondo is ad-hoc signed and not notarized, so the first launch needs
**right-click the app, then Open**, and confirming once. Double-clicking it
gives an error instead, with no way forward. Notarizing needs a paid Apple
Developer ID, which this project does not have.

It runs on Apple Silicon, macOS 14 or later. There is no Intel build: one
would need the Rust target added to the dev shell and both slices merged.

## Layout

```text
crates/rondo-core/   Domain model, cycle math, storage, backup (Rust)
crates/rondo-ffi/    UniFFI bindings for frontends in other languages
apple/               SwiftUI application for macOS (iOS later)
scripts/             Build helpers (XCFramework, packaging)
```

Building it, in short: `scripts/build-xcframework.sh`, then
`xcodegen generate --spec apple/project.yml --project apple`, then open
`apple/Rondo.xcodeproj`. [docs/development.md](docs/development.md) has the
environment it expects.

## Documentation

- [Architecture](docs/architecture.md) - the shared-core shape and the domain rules.
- [Development](docs/development.md) - environment, checks, and workflow.
- [Roadmap](docs/roadmap.md) - milestones and non-goals.

## License

MIT. See [LICENSE](LICENSE).
