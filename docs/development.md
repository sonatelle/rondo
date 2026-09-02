# Development

## Environment

The toolchain is pinned by the Nix flake (based on the Sonatelle
[Prelude](https://github.com/sonatelle/prelude) dev-shell module).

1. Install [Nix](https://nixos.org) and [direnv](https://direnv.net).
2. `direnv allow` in the repository root; the Rust toolchain appears in
   your shell.

Without direnv, prefix commands with `nix develop -c`; in non-interactive
shells use `direnv exec . <cmd>`.

## Checks

Every change must pass, locally and in CI:

```sh
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

CI runs the same three commands inside `nix develop` on Ubuntu and macOS
for every pull request and every push to `main`.

## The Swift bridge

Packaging the core for Xcode, and checking that the package works:

```sh
scripts/build-xcframework.sh          # apple/RondoCore/
scripts/swift-smoke-test.sh           # compiles and runs apple/smoke
```

Run both after changing anything in `rondo-ffi`. The smoke test is what
catches a package that builds but cannot be used: the Rust tests never
link the packaged artifact, so only compiling real Swift against it shows
whether Xcode could.

To look at the generated bindings without packaging them, the generator
runs on its own. It lives behind a feature so its dependencies stay out of
the library the app ships:

```sh
cargo build -p rondo-ffi
cargo run --features bindgen -p rondo-ffi --bin uniffi-bindgen -- generate \
    --library target/debug/librondo_ffi.dylib --language swift --out-dir /tmp/bindings
```

## The macOS app

The Xcode project is generated from `apple/project.yml`, so settings are
edited there and not in Xcode's inspector - anything changed in the
inspector is lost on the next generate. Xcode's "update to recommended
settings" prompt is the same trap; note down what it offers and add the
equivalent to the spec.

```sh
scripts/build-xcframework.sh          # the app links this
xcodegen generate --spec apple/project.yml --project apple
xcodebuild test -project apple/Rondo.xcodeproj -scheme Rondo -destination 'platform=macOS'
```

Then open `apple/Rondo.xcodeproj` and run, or launch the built `.app`.

For an editor other than Xcode, sourcekit-lsp needs to know where the
build is. [xcode-build-server](https://github.com/SolaWing/xcode-build-server)
writes that down, once per checkout, after the project exists:

```sh
xcode-build-server config -project apple/Rondo.xcodeproj -scheme Rondo
```

It is not in nixpkgs, so install it separately (`brew install
xcode-build-server`). The `buildServer.json` it writes holds absolute
paths to this machine, and is not in version control.

The app icon is drawn by a script rather than kept as artwork:

```sh
scripts/make-app-icon.swift apple/Rondo/Assets.xcassets/AppIcon.appiconset
```

Its PNGs are committed. Nothing regenerates them during a build - there
are no script phases in this project, deliberately - so run it after
editing the mark and commit what it writes. The mark's proportions and
palette are the constants at the top of the script.

`build-xcframework.sh` builds for this machine by default. Another target
(Intel macOS, iOS) needs its standard library added to the Rust toolchain
in `flake.nix` first; the script says so rather than failing obscurely.

The app is pinned to `arm64` to match. Left at its default, Release asks
for a universal binary and fails to link, since the framework carries no
Intel slice - and Debug hides this, because it builds only the
architecture it is running on. Supporting Intel means adding the target,
merging both slices, and lifting `ARCHS` in `apple/project.yml` together.

## Words on screen

Every string the interface shows lives in `apple/Rondo/Localizable.xcstrings`,
in English and Simplified Chinese. Adding a language is a matter of adding
it to that catalogue: the picker in Settings is built from whatever the
bundle carries, so no Swift changes.

Two things do not extract themselves, and both fail silently:

- `Text(someString)` is the verbatim initializer. It shows the text as
  written and never looks anything up, so a title passed as a `String`
  stays in English. Pass a `LocalizedStringKey`.
- A sentence assembled in Swift - a count and a noun, a list joined with
  "and" - can only ever be English. Ask for the whole phrase with
  `String(localized:)` and let the catalogue carry the grammar.

**`xcodebuild` does not write new keys back into the catalogue.** The
compiler extracts them into `.stringsdata`, and Xcode's own sync is what
copies them across; a command-line build leaves the catalogue as it was, so
new text quietly appears untranslated. After adding strings, sync from the
compiler's own list:

```sh
find ~/Library/Developer/Xcode/DerivedData -path '*Rondo.build/Debug*' -name '*.stringsdata'
```

Each is a plist or JSON holding the keys from one source file. Anything
there but not in the catalogue is a string nobody can translate yet;
anything in the catalogue but not there is a leftover.

Three tests guard the catalogue, and each was checked by breaking it on
purpose: every language is translated all the way through, Chinese
sentences use Chinese punctuation, and a translation keeps the format
specifiers its key had.

## The backup format

The format is versioned by `backup::FORMAT_VERSION`. Import migrates
anything older and refuses anything newer, since a build cannot know what
a field it has never seen means.

- **Version 1** carried one price per subscription.
- **Version 2** carries a price history, and payment methods. Importing a
  version 1 file opens a history holding its one price, effective from the
  first charge - the same reconstruction the schema migration performs, so
  a database restored from a file matches one migrated in place.

Raising it again means: bump the constant, keep reading every earlier
shape, and say so in the release notes. **A backup written after a bump
cannot be read by builds from before it**, and that is the only
incompatibility a person using Rondo can run into, so it deserves a release
of its own to point at.

Two tests hold this down, and both were checked by breaking them on
purpose: a version 1 file restores with the history rebuilt and its
timestamps intact, and restoring the same file twice leaves one history
rather than two.

## Two version numbers

The app and the core are versioned apart, because they change apart.

- **The app** is `MARKETING_VERSION` in `apple/project.yml`, and it is what
  a release tag names. It moves whenever a release goes out, whether or not
  the Rust side was touched.
- **The core** is `version` in the workspace `Cargo.toml`, shared by
  `rondo-core` and `rondo-ffi`. It moves only when the core's own surface
  does - the FFI records, the schema, the backup format - and follows
  semver on that surface. Below 1.0 a breaking change is a minor bump, so
  reshaping a record or raising `backup::FORMAT_VERSION` moves the minor.

So the two differing is normal, and the About screen shows both on purpose.
What it catches is the pair drifting the wrong way: an app several releases
along still reporting the core it shipped with means the bundle was built
against a stale `RondoCore.xcframework`.

The crates are not published anywhere, so nothing outside this repository
reads the core's version. Its audience is that About line and whoever is
deciding whether a change to the core is breaking. If another frontend ever
ships on its own schedule, that is the moment the number gains a real
consumer.

## Cutting a release

```sh
scripts/package-dmg.sh          # dist/Rondo-<version>.dmg
```

The version in the file name is read from the app that was built, not from
any file that claims one, so the name cannot disagree with what the app
reports about itself.

A release is cut by pushing a tag; the workflow runs this same script, so
a release is never built by a path that has only ever run in CI:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

What it leaves behind is a **draft** release with the image attached.
Read the notes, then publish it from the Releases page - a published
release is the one thing here that cannot be taken back once people have
downloaded it.

The tag and `MARKETING_VERSION` in `apple/project.yml` have to agree, and
the workflow fails early if they do not - otherwise a forgotten version
bump ships a release holding an app that calls itself something else.

Whatever the README says about the new version belongs in that same
version-bump pull request, before the tag is pushed. Written afterwards, it
lands between two tags and the next release's generated notes advertise it
as a change of their own - which is how v0.2.0 came to list "Point the
README at the v0.1.0 release". Only the roadmap's published line has to
wait, since publishing is a decision made after the tag exists.
Re-run the workflow by hand (choosing the tag as the ref) rather than
deleting and re-pushing a tag when publishing fails for its own reasons.

The app is ad-hoc signed and not notarized, so a downloaded copy needs
right-click - Open on first launch. Notarizing needs a paid Developer ID.

## Workflow

- All work lands through pull requests; `main` stays stable. One
  short-lived branch per independent change, merged with
  `Rebase and merge`, branch deleted afterwards.
- Commits are small and single-intent, with Conventional Commits subjects
  (`feat(core): ...`, `docs: ...`, `ci: ...`). Each commit builds and
  passes the checks at its own tree state, so history stays bisectable.
- Land each unit as soon as it stands alone and passes checks - write,
  verify, commit, then start the next unit.

The full conventions, including architecture rules an agent must follow,
live in [AGENTS.md](../AGENTS.md).
