//! Domain model, billing-cycle math, storage, and import/export for Rondo.
//!
//! This crate owns every business rule of the subscription tracker; UI
//! layers (SwiftUI and future frontends) stay thin and call in through
//! `rondo-ffi`. Nothing here touches the network or a specific platform.

pub mod backup;
pub mod cycle;
pub mod error;
pub mod model;
pub mod store;
pub mod summary;
pub mod templates;

pub use backup::Backup;
pub use error::{Error, Result};
pub use model::{BillingCycle, Category, CycleUnit, Money, Subscription, SubscriptionStatus};
pub use store::Store;
pub use templates::ServiceTemplate;
