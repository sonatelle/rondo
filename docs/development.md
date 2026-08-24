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

`build-xcframework.sh` builds for this machine by default. Another target
(Intel macOS, iOS) needs its standard library added to the Rust toolchain
in `flake.nix` first; the script says so rather than failing obscurely.

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
