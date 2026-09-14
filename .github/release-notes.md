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

An analytics page: where the money went, and when.

Four figures to start — what has been charged this year, what has been
charged ever, what it comes to in a month, and how many subscriptions are
running. Where no rate reaches an amount you get a dash rather than a zero,
because a total with nothing behind it is unknown rather than nothing.

Under them, a bar for each of the last twelve months, with what was
actually charged written above it. Months already billed are drawn a step
fainter than the ones still to come, and a forecast month is deliberately
left without a figure: a number that has not happened yet should not sit
on the page looking like one that has. The scale runs to the tallest month
rather than to a round number, since the question is which months stand
out. When one does and a yearly plan explains it, a line beside the chart
says so by name.

Then a bar for each subscription, showing what it has cost since its first
charge, and a split by category — each slice in your own currency, adding
up to exactly the monthly figure in the card above. You can switch the
chart between the last twelve months and this calendar year.

Nothing about your data changed in this release.

## Known

Opening Rondo from the menu bar can leave the File menu drawn as though it
were open. Clicking anywhere clears it, and no menu is really open — it is
the menu bar left unrepainted. It is not fixed here.

## Before you upgrade

**A backup written by v0.5.0 or later cannot be read by v0.4.0 or earlier.**
The format carries hand-entered exchange rates, and a build refuses a format
newer than its own by design. Backups from older versions restore here as
they always did.

Only rates you typed are carried in a backup. Fetched ones can be had from
the source again; one you set by hand exists nowhere else.
