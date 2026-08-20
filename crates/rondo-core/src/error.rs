//! Structured errors shared across rondo-core.

use thiserror::Error;

/// Errors produced by rondo-core operations.
#[derive(Debug, Error)]
pub enum Error {
    /// A billing cycle was constructed with an out-of-range count.
    #[error("invalid billing cycle: {0}")]
    InvalidCycle(String),

    /// A money value violated an invariant (negative amount, bad currency).
    #[error("invalid money value: {0}")]
    InvalidMoney(String),

    /// A subscription field violated an invariant (e.g. empty name).
    #[error("invalid subscription: {0}")]
    InvalidSubscription(String),

    /// A billing-date computation left the supported calendar range.
    #[error("billing date out of range: {0}")]
    DateOutOfRange(String),
}

/// Convenience result alias for rondo-core operations.
pub type Result<T> = std::result::Result<T, Error>;
