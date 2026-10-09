//! How failures cross the language boundary.

use rondo_core::Error as CoreError;
use thiserror::Error;

/// A failure reported to a frontend.
///
/// The core distinguishes eight failure kinds, but a user interface only
/// has four responses available: point at the field the person can fix,
/// report that the database is misbehaving, tell them the stored data is
/// unusable and offer a backup, or say that this copy of Rondo is the one
/// behind. Grouping by the response keeps the foreign-facing surface small
/// and stable while `message` carries the specifics for the text the
/// person actually reads.
#[derive(Debug, Error, uniffi::Error)]
pub enum RondoError {
    /// A value the person entered is not acceptable.
    #[error("{message}")]
    InvalidInput { message: String },

    /// The database could not be read or written.
    #[error("{message}")]
    Storage { message: String },

    /// Stored data no longer satisfies the rules the app relies on.
    ///
    /// This means the file was written by another tool or an incompatible
    /// version. It is not something retrying will fix.
    #[error("{message}")]
    UnusableData { message: String },

    /// The database was written by a newer Rondo than this one.
    ///
    /// Apart from `Storage` because nothing is wrong: the file is whole and
    /// the person's data is safe. Only this build is behind, and the thing
    /// to say is "update Rondo" - advice that would be wrong, and alarming,
    /// for any other storage failure.
    #[error("{message}")]
    DatabaseTooNew { message: String },
}

impl From<CoreError> for RondoError {
    fn from(error: CoreError) -> Self {
        let message = error.to_string();
        match error {
            CoreError::InvalidCycle(_)
            | CoreError::InvalidMoney(_)
            | CoreError::InvalidSubscription(_)
            | CoreError::InvalidRate(_)
            | CoreError::DateOutOfRange(_) => Self::InvalidInput { message },
            CoreError::Storage(_) | CoreError::Migration(_) => Self::Storage { message },
            CoreError::Corrupt(_) => Self::UnusableData { message },
            CoreError::DatabaseTooNew => Self::DatabaseTooNew { message },
        }
    }
}

/// Result alias for everything exported to a frontend.
pub type Result<T> = std::result::Result<T, RondoError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validation_failures_point_at_the_person_s_input() {
        let error = CoreError::InvalidMoney("negative amount -1".into());
        let RondoError::InvalidInput { message } = RondoError::from(error) else {
            panic!("a rejected amount is the person's input to fix");
        };
        // The detail survives, so the frontend has something to show.
        assert!(message.contains("negative amount -1"), "{message}");
    }

    #[test]
    fn database_failures_are_reported_as_storage() {
        let error = CoreError::Storage(rusqlite_error());
        assert!(matches!(
            RondoError::from(error),
            RondoError::Storage { .. }
        ));
    }

    #[test]
    fn corrupt_rows_are_not_something_retrying_fixes() {
        let error = CoreError::Corrupt("unknown cycle unit \"fortnight\"".into());
        assert!(matches!(
            RondoError::from(error),
            RondoError::UnusableData { .. }
        ));
    }

    #[test]
    fn a_newer_database_is_not_reported_as_a_broken_one() {
        // The distinction the whole variant exists for: told apart from
        // `Storage`, the frontend can say "update Rondo" instead of
        // claiming the database is at fault when it is not.
        assert!(matches!(
            RondoError::from(CoreError::DatabaseTooNew),
            RondoError::DatabaseTooNew { .. }
        ));
    }

    /// Produces a real rusqlite failure without needing a database.
    fn rusqlite_error() -> rusqlite::Error {
        rusqlite::Error::QueryReturnedNoRows
    }
}
