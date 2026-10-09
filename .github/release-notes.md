## Installing

```sh
brew install --cask sonatelle/tap/rondo
```

Or download the disk image below, open it, and drag Rondo to Applications.

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

It runs on Apple Silicon Macs, macOS 14 or later. There is no Intel build.

Rondo keeps its data in a local SQLite file. It has no account and sends
nothing about you anywhere. From v0.5.0 it fetches exchange rates, and
that is the only thing it asks the network for.

## What's new

Three rounds arrive together, and between them they finish the eighteen
screens the design asked for.

**Analytics.** Where the money has gone, rather than where it goes next:
what each month cost over the span you choose, which month was the most
expensive, what each subscription has taken since its first charge, and how
the whole comes apart by category. Every figure is one currency's worth,
levelled by month so a yearly plan counts as a twelfth of itself.

**The list, gathered by what pays for it.** Or by category, currency, or
where it was bought — with each group's own monthly total beside its name.
Those totals are asked of the core one group at a time rather than added up
here, so a heading and the rows under it cannot come to different numbers.

**The archive, as a page of its own.** What you stopped paying for, how
long it ran, and what it cost altogether while it did. It is the one page
whose sums deliberately take no notice of whether a subscription is still
active, and the reason the database now records the day a subscription was
archived — which it never kept before.

**Reminders, which is the part that works while Rondo is closed.** A
notification a few days before a charge, at an hour you set, with the days
of warning set per subscription. Two buttons on it: one opens that
subscription, one puts it off until tomorrow — and the one that puts it off
rewrites what it says, because "charged in 2 days" is true on the day it
was written for and wrong on the next one. Permission is asked for when you
turn reminders on, never at launch.

On the first of each month there is a quieter one: what the month ahead
comes to, with no buttons and no sound. If a currency has no rate, it says
so rather than showing a total that is quietly short.

**A first run that says what Rondo is for**, shown only to a database with
nothing in it — restoring a backup is not somebody's first day.

**And a plain sentence when a file is from the future.** Opening a database
written by a newer Rondo used to show a line of Rust: "Attempt to migrate a
database with a migration number that is too high". It now says that
nothing is wrong and nothing has been lost, and offers the releases page.

## Known

Opening Rondo from the menu bar can leave the File menu drawn as though it
were open. Clicking anywhere clears it, and no menu is really open — it is
the menu bar left unrepainted. It is not fixed here.

## Before you upgrade

**Once v0.7.0 has opened your database, v0.6.0 and earlier cannot open it
again.** This release adds a column to it, and a build refuses a schema
newer than the one it knows — the same rule in the other direction from the
one below. It has been true of every release that changed the database, but
this is the first to say so, and the first where the app explains itself
instead of printing the error it got. Keep a backup before upgrading if you
might want to go back.

**A backup written by v0.7.0 cannot be read by v0.6.0 or earlier.** The
format carries the day a subscription was archived, which older builds know
nothing about. Backups from older versions restore here as they always did.
