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

Four corrections to the menu bar window, which v0.5.0 left behind when every
other screen learned to convert.

Its list of what renews next still showed each charge in the currency it is
billed in, sitting directly above a total in yours with nothing joining them.
Those rows are converted now.

Settings did not open from that window at all, and the shortcut printed
beside the row did nothing when pressed. Both work. The keys named in this
window are bound to it now, which is what they needed: with no main window
open Rondo is an accessory and has no menu bar of its own for them to come
from.

The shortcuts also line up down the list rather than sitting wherever the
last character left them, and no row is drawn fainter than the ones above
it.

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
