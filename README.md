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

Early development. The macOS app runs and keeps real data, but there is no
release to download yet: it has to be built from source.

What works:

- Record subscriptions with a price, a billing cycle, and a first charge,
  starting from a bundled service or from nothing.
- See what renews next, and what it all costs per month, per currency.
- Edit, archive, restore, and delete.
- Local SQLite storage. No cloud, no account, no network.

Still to come:

- Renewal reminders through local notifications.
- Backup export and restore from the app; the core already does both.
- A release you can download.

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
