//! UniFFI bindings over `rondo-core` for platform frontends.
//!
//! This crate is a translation layer and nothing else: it adapts core types
//! to the shapes UniFFI can carry across the language boundary. Business
//! rules belong in `rondo-core`, where they can be tested without a
//! foreign runtime.

mod types;

uniffi::setup_scaffolding!();

/// Version of the Rondo core linked into this build.
///
/// Frontends show this in their about screen, and it is the quickest way
/// to tell whether an app bundle picked up a stale library.
#[uniffi::export]
pub fn library_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_reported_version_matches_the_crate() {
        assert_eq!(library_version(), env!("CARGO_PKG_VERSION"));
    }
}
