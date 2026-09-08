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

Every total is now one figure in a currency you pick, rather than a list of
one per currency. Each amount shows what it comes to over what it is
actually billed at, and a total names what went into it.

Charges are converted at the rate of the day they fell on, so a total over
past months does not move when today's rate does. There is a switch if you
would rather price everything at today's rate, and its description says what
that costs.

Rates come from frankfurter.dev, once a day if you let it. You can type a
rate in yourself and no update will overwrite it. Anything Rondo has no rate
for is shown in the currency it is billed in — never converted at a number
nobody checked, and never at 1:1.

Settings gains a Currency tab: which currency to total in, when rates were
last brought up to date, and a rate per currency you can overrule.

## Before you upgrade

**A backup written by v0.5.0 cannot be read by v0.4.0 or earlier.** The
format carries hand-entered exchange rates now, and a build refuses a format
newer than its own by design. Backups from older versions restore here as
they always did.

Only rates you typed are carried in a backup. Fetched ones can be had from
the source again; one you set by hand exists nowhere else.
