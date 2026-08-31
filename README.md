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

v0.1.0 is out. The macOS app runs and keeps real data.

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
- Local SQLite storage. No cloud, no account, no network.

Still to come:

- Renewal reminders through local notifications.
- A look of its own. The app is shaped like a macOS app now, but plain.

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
