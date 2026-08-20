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

    /// The underlying SQLite database failed.
    #[error("storage error: {0}")]
    Storage(#[from] rusqlite::Error),

    /// A stored row no longer satisfies a domain invariant.
    ///
    /// This means the database was edited outside Rondo or written by an
    /// incompatible version; refusing to load it beats silently repairing.
    #[error("corrupt data: {0}")]
    Corrupt(String),
}

/// Convenience result alias for rondo-core operations.
pub type Result<T> = std::result::Result<T, Error>;
