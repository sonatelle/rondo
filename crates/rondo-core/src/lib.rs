//! Domain model, billing-cycle math, storage, and import/export for Rondo.
//!
//! This crate owns every business rule of the subscription tracker; UI
//! layers (SwiftUI and future frontends) stay thin and call in through
//! `rondo-ffi`. Nothing here touches the network or a specific platform.

pub mod cycle;
pub mod error;
pub mod model;

pub use error::{Error, Result};
pub use model::{BillingCycle, Category, CycleUnit, Money, Subscription, SubscriptionStatus};
