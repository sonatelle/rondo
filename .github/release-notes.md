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

A calendar, which answers the question the lists do not: not what you are
paying for, but which day it leaves.

A month is six rows of days with each charge drawn in the day it falls on,
coloured by how soon that is — the same red and amber the rest of Rondo
uses and nothing else. Above the grid, what the month comes to and how many
charges make it. That figure is those chips added up, not a second sum that
could disagree with them.

There is a year view too, and it exists for one reason. A yearly plan lands
its whole price in one month and nothing in the other eleven, and from
inside any single month you cannot see that coming. So the year shows
twelve cards with what each costs, names the yearly plan landing in each,
and marks the month that turns out to be the most expensive. Under every
card is a strip of thirty-one marks saying only *whether* a day carries a
charge — a yearly one picked out from the rest. Click a month to open it.

Amounts follow the same rules as everywhere else: the converted figure
where a rate reaches it, what it is really billed at where none does.

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
