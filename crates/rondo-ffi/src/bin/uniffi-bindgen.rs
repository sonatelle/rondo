//! Binding generator entry point, run by the build scripts.
//!
//! UniFFI generates foreign-language bindings by inspecting the compiled
//! library, so the generator ships as its own binary behind the `bindgen`
//! feature rather than as part of the library the app links.

fn main() {
    uniffi::uniffi_bindgen_main()
}
