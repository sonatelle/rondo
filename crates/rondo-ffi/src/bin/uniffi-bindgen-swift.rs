//! Swift-specific binding generator, run by the packaging script.
//!
//! UniFFI ships a dedicated entry point for Swift that can emit sources,
//! headers, and the module map separately, each to its own directory. That
//! is what an XCFramework wants, and it saves the packaging script from
//! sorting and renaming the generator's output by hand.

fn main() {
    uniffi::uniffi_bindgen_swift()
}
