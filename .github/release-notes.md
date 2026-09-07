## Installing

Download the disk image, open it, and drag Rondo to Applications.

Rondo is ad-hoc signed and not notarized, so macOS stops the first launch,
and how you get past it depends on the version. On macOS 14 it is
**right-click the app, then Open**, and confirm once. macOS 15 removed that
route: open the app, let it be refused, then go to **System Settings >
Privacy & Security**, find the notice near the bottom, and press **Open
Anyway**. Either way it is asked once. Notarizing needs a paid Apple
Developer ID, which this project does not have.

It runs on Apple Silicon Macs, macOS 14 or later. There is no Intel build.

Rondo keeps its data in a local SQLite file and makes no network requests
of any kind.
