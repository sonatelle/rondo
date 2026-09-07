//! UniFFI bindings over `rondo-core` for platform frontends.
//!
//! This crate is a translation layer and nothing else: it adapts core types
//! to the shapes UniFFI can carry across the language boundary. Business
//! rules belong in `rondo-core`, where they can be tested without a
//! foreign runtime.

pub mod error;
pub mod records;
pub mod rondo;
pub mod types;

pub use error::{Result, RondoError};

uniffi::setup_scaffolding!();

/// Version of the Rondo core linked into this build.
///
/// Frontends show this in their about screen, and it is the quickest way
/// to tell whether an app bundle picked up a stale library.
#[uniffi::export]
pub fn library_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

/// The currency every stored exchange rate is quoted against.
///
/// A frontend fetching rates must ask its source for this base, and the
/// rates it hands back must be units of each currency per one unit of it.
/// Exposed rather than written into the frontend so the two can never
/// disagree about which currency the stored numbers mean.
#[uniffi::export]
pub fn base_currency() -> String {
    rondo_core::BASE_CURRENCY.to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_reported_version_matches_the_crate() {
        assert_eq!(library_version(), env!("CARGO_PKG_VERSION"));
    }

    #[test]
    fn the_base_currency_is_the_core_s_own() {
        // A copy of the code here rather than a reference to it would be a
        // second source of truth, and the kind that goes wrong silently.
        assert_eq!(base_currency(), rondo_core::BASE_CURRENCY);
    }
}
