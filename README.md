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

Early development. Nothing is usable yet.

Planned for the first release:

- Record subscriptions with price, billing cycle, and next billing date.
- Renewal reminders through local notifications.
- Monthly and yearly spending summaries.
- Local SQLite storage with JSON import and export. No cloud, no account.

## Layout

```text
crates/rondo-core/   Domain model, cycle math, storage, import/export (Rust)
crates/rondo-ffi/    UniFFI bindings for platform frontends (Rust)
apple/               SwiftUI application for macOS (iOS later)
scripts/             Build helpers (XCFramework, packaging)
```

## Documentation

- [Architecture](docs/architecture.md) - the shared-core shape and the domain rules.
- [Development](docs/development.md) - environment, checks, and workflow.
- [Roadmap](docs/roadmap.md) - milestones and non-goals.

## License

MIT. See [LICENSE](LICENSE).
