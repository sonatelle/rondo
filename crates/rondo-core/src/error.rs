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

    /// An exchange rate was not a positive number, or was quoted for
    /// something that is not a currency code.
    #[error("invalid exchange rate: {0}")]
    InvalidRate(String),

    /// A billing-date computation left the supported calendar range.
    #[error("billing date out of range: {0}")]
    DateOutOfRange(String),

    /// The underlying SQLite database failed.
    #[error("storage error: {0}")]
    Storage(#[from] rusqlite::Error),

    /// The database schema could not be brought up to date.
    #[error("schema migration failed: {0}")]
    Migration(rusqlite_migration::Error),

    /// The database was written by a newer Rondo than this one.
    ///
    /// Its own variant rather than one more `Migration`, because it is the
    /// only schema failure that is not a fault: the file is intact, nothing
    /// is broken, and a later build opens it. What a frontend has to say
    /// about it is therefore completely different from what it says about a
    /// migration that genuinely failed - so the fact is named here, and the
    /// sentence is left to the side that can write one.
    #[error("database written by a newer version of Rondo")]
    DatabaseTooNew,

    /// A stored row no longer satisfies a domain invariant.
    ///
    /// This means the database was edited outside Rondo or written by an
    /// incompatible version; refusing to load it beats silently repairing.
    #[error("corrupt data: {0}")]
    Corrupt(String),
}

/// Sorts a schema failure into the one case worth telling apart.
///
/// Written out rather than derived with `#[from]` so that every `?` on a
/// migration call classifies it, and none can be added later that forgets
/// to. The match is on the variant and never on the message: the crate
/// documents that its `Display` text may change in a patch release.
impl From<rusqlite_migration::Error> for Error {
    fn from(error: rusqlite_migration::Error) -> Self {
        match error {
            rusqlite_migration::Error::MigrationDefinition(
                rusqlite_migration::MigrationDefinitionError::DatabaseTooFarAhead,
            ) => Self::DatabaseTooNew,
            other => Self::Migration(other),
        }
    }
}

/// Convenience result alias for rondo-core operations.
pub type Result<T> = std::result::Result<T, Error>;
