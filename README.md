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

v0.4.0 is out. The macOS app runs and keeps real data.

**Backups written by v0.3.0 and later cannot be read by v0.1.0 or v0.2.0.** They
carry a price history those builds know nothing about, and a build refuses
a format newer than its own by design. Backups written by the older builds
restore here as they always did.

What works:

- Record subscriptions with a price, a billing cycle, and a first charge,
  starting from a bundled service or from nothing. Searching the services
  finds them by nickname too: "B站" finds Bilibili.
- File a subscription under a category, say where it was bought, whose
  account it bills to, and which card pays for it.
- See what renews next, and what it all costs per month, per currency.
- Read the whole list as a table of seven columns, sorted by any of them,
  narrowed by a search over names and accounts or by channel and currency.
  What is left is totalled per month at the top.
- Open one subscription to see what it has cost since its first charge,
  every charge it has fallen due for, and where a price rose.
- Be told where to go to cancel it, which depends on where it was bought.
- Keep a price history: correcting a price is not the same as recording a
  rise, so totals across a rise are the real number rather than today's
  price multiplied out.
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

v0.4.0 is where the main window becomes the one in the design. v0.3.0 had
taught the data model price history, payment methods and category icons
without showing any of it; this is the release that shows it — the
overview, the form and its provider picker, the table with those fields
spread across it, and a page for one subscription.

Still to come:

- One total rather than one per currency. v0.5.0 converts to a currency
  you pick, which is the first thing Rondo will use the network for: it
  fetches exchange rates, and nothing else. Until then currencies are
  listed apart and never converted.
- A calendar of what falls due, and an analytics page.
- Spending grouped by payment method, and the archive as a page of its own.
- First run, and renewal reminders through local notifications.

## Install

```sh
brew install --cask sonatelle/tap/rondo
```

Or [download the latest release](https://github.com/sonatelle/rondo/releases/latest),
open the disk image, and drag Rondo to Applications.

Rondo is ad-hoc signed and not notarized, because notarizing needs a paid
Apple Developer ID, which this project does not have. The two routes differ
in who deals with that.

The disk image leaves it to you. macOS stops the first launch, and how you
get past it depends on the version: on macOS 14 it is **right-click the app,
then Open**, and confirm once; macOS 15 removed that route, so open the app,
let it be refused, then go to **System Settings > Privacy & Security**, find
the notice near the bottom, and press **Open Anyway**. Either way it is
asked once.

[The tap](https://github.com/sonatelle/homebrew-tap) settles it for you
instead: the cask clears the quarantine attribute Homebrew applies, so the
app opens straight away. That is a real waiver of Gatekeeper's check for
this one app, made without asking - worth knowing before taking the shorter
command.

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
