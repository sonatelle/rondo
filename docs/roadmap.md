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
      needs getting past Gatekeeper by hand, in a way that changed in
      macOS 15
- [x] A Homebrew tap, written to by the release that publishes, 2026-09-07
- [x] v0.1.0 published, 2026-08-28
- [x] v0.2.0 published, 2026-09-01
- [x] v0.3.0 published, 2026-09-03 - the release the backup format moved in
- [x] v0.4.0 published, 2026-09-06 - the release the main window arrived in

The tap is `sonatelle/homebrew-tap`, and it has to be a tap of our own:
homebrew-cask stopped taking casks that fail Gatekeeper on 2026-09-01, and
Homebrew removed the `--no-quarantine` flag in 5.1, so an unnotarized app
has nowhere else to go. The cask clears the quarantine attribute itself,
which buys a one-command install at the price of waiving Gatekeeper's check
without asking. Signing and notarizing would undo both the exclusion and the
waiver; it needs a paid Developer ID.

Pushing to the tap needs a token for another repository, held here as the
`HOMEBREW_TAP_TOKEN` secret. When it expires the release still succeeds and
the tap quietly stops moving, so `brew install` goes on handing people an
old version with nothing saying why. The workflow can be re-run by hand
against a tag once a new token is in place.

## M6 - The design handoff (in progress)

Eighteen screens, delivered as a hifi design in August 2026 and widened
twice in September. It is named a milestone of its own because it is not a coat of
paint: most of the screens did not exist, the overview was a rewrite rather
than a restyle, and the handoff asked the core for price history, payment
methods and a provider table. One round per pull request, in dependency
order; the version each round ships in is named, because one of them
changes the backup format and that needs a boundary a reader can point at.

- [x] Design tokens, the menu bar window, the settings shell - v0.2.0
- [x] A bilingual interface with a language of its own to pick - v0.2.0
- [x] A provider table, with aliases to search by - v0.3.0
- [x] Price history, payment methods, category icons - one migration, and
      the backup format to v2 - v0.3.0
- [x] The aggregations the analytics screen needs - v0.3.0
- [x] Sidebar navigation and the overview - v0.4.0
- [x] The form, picking a provider, and the full table - v0.4.0
- [x] Subscription detail, and where to cancel by channel - v0.4.0
- [ ] Exchange rates, conversion, and the currency settings - v0.5.0
- [ ] The amount display rules, across every screen that prints money -
      v0.5.0
- [ ] The calendar and its year view - v0.6.0
- [ ] Analytics - v0.7.0
- [ ] Spending grouped by payment method, and the archive - v0.8.0
- [ ] First run, and local notifications - which also closes M4 - v0.9.0

v0.3.0 was the release to be careful with. Its screens barely changed, but
a backup written after it cannot be read by v0.1.0 or v0.2.0, which refuse
formats from the future by design.

v0.4.0 carried three rounds rather than two: the fields v0.3.0 added got
their whole interface at once, so recording a price change and seeing the
history arrived together rather than a version apart.

Where to cancel came a version early, in v0.4.0 rather than v0.8.0. Its
entry is a button in the detail page's header, and building that page
twice - once without it and once with - would have cost more than building
it once.

Two things v0.4.0 found rather than planned. The first: round 4 had built
payment methods with their whole CRUD across the boundary, and nothing in
the interface could create one, so the picker offered an empty list and
the column beside it was always blank. Naming and removing one now happens
where somebody discovers they need it, in the form.

The second is older than the round that found it: a `LocalizedStringKey`
resolves against the system's language rather than the one chosen in
settings, so the interface was half
translated for anybody whose Mac disagreed with their choice. Every string
now goes through `Localization.bundle`, and two tests hold it there. The
words macOS supplies itself - the File and Edit menus, the standard items
in the app menu - still follow the system, because AppKit fixes its own
language when the process starts. Changing that means relaunching, which
is a decision rather than a fix.

The design gained five screens in September, and the plan two rounds. Three
of them - the full subscription table, the archive, the empty states - are
completions of pages already being built and were folded into the rounds
that build them. The other two earn a round each: grouping spending by
payment method needs an aggregation the core does not have, and telling
somebody where to cancel is the reason the channel field exists at all.

Grouping by payment method reverses a decision made in round 4, which was
not to aggregate them. That rested on the analytics design having no such
view; the September design has one, so the aggregation now has a screen
that can show it is wrong.

The design was widened a second time at the end of the month, and this one
reordered the rest of the plan. Every total becomes a single figure in a
primary currency, which reverses the oldest rule the project had about
money - that currencies are listed apart and never converted - and brings
two screens of its own, the currency settings and a sheet of rules for how
an amount is written. Rates come from the network, which Rondo had not
done at all. `AGENTS.md` carries what that cost and why it was accepted.

So currency goes first, before the calendar and the analytics rather than
after them. Both of those screens are almost entirely numbers; built under
the old rule they would be built twice.

An exchange rate is stored as a history, in the shape a price already has,
rather than as a rate locked onto each charge the way the handoff
describes. The two agree about the answer - a charge is converted at the
rate of its own day, and a total does not move when rates do - but a
charge in Rondo is derived from the anchor date and the cycle rather than
written down, so there is no row to lock a rate onto. Writing one would
mean a ledger, a thing to keep in step with the schedule it was derived
from, and a class of bug where editing a first billing date leaves stale
rows behind. The rate source having a historical endpoint settles the one
argument the ledger had: rates from before Rondo was installed can be
fetched rather than only accumulated.

The source is Frankfurter, `api.frankfurter.dev/v2`, verified on
2026-09-07: no key, 201 currencies from 84 official sources, and open
source with a self-hosted option if it ever goes away. It answers for one
day (`?date=`), for a range (`?from=&to=`, optionally grouped by month),
and for only the currencies asked about (`?base=&quotes=`), which is what
makes backfilling a subscription's whole history one request rather than
one per charge. Its v1 nested `rates` object is superseded by v2's flat
arrays; write against v2.

Two more fields fall out of the widened design: `cancel_url` on the
provider table, which round 8 was told to skip and which the guide to
cancelling can use once it exists, and `archived_at`, which the archive
screen needs to say how long something ran. Both are migrations, and both
wait for the round that shows them.

## Later, undated

- iOS delivery (blocked on a distribution story outside GitHub Releases)
- Windows / Linux / Android frontends against the same core
- Device sync (the data model already reserves ids and timestamps)

## Non-goals for the MVP

Tags, widgets, accounts, and App Store integrations are deliberately out of
scope until the MVP is done.

Currency conversion and charts were on this list until 2026-09-07, when the
design made both of them the point of a screen. `AGENTS.md` records the
decision and what it withdrew.
