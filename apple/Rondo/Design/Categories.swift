import SwiftUI

/// How a category looks and reads on this platform.
///
/// The core stores semantic keys - `"video"`, `"pink"` - and never a symbol
/// name or a hex value, because it is shared: an SF Symbol name would reach
/// an Android frontend as a string it could do nothing with, and one hex
/// value cannot serve both a light and a dark theme. Turning a key into
/// something to draw is this side's job, and this is where it happens.
enum Categories {
  /// The symbol for an icon key, falling back to a plain tag for a key this
  /// build has never heard of - a category made by a newer version, or one
  /// somebody edited into the database by hand.
  static func symbol(for iconKey: String?) -> String {
    switch iconKey {
    case "video": "play.rectangle.fill"
    case "music": "music.note"
    case "reading": "book.fill"
    case "games": "gamecontroller.fill"
    case "tools": "wrench.and.screwdriver.fill"
    case "ai": "sparkles"
    case "dev": "curlybraces"
    case "storage": "externaldrive.fill"
    default: "tag.fill"
    }
  }

  /// The colour for a colour key, falling back to the app's accent.
  ///
  /// The asset is named for the key rather than for the category, so that
  /// what the core stores and what the catalogue holds are the same word.
  static func tint(for colorKey: String?) -> Color {
    switch colorKey {
    case "pink": .categoryPink
    case "violet": .categoryViolet
    case "green": .categoryGreen
    case "red": .categoryRed
    case "amber": .categoryAmber
    case "teal": .categoryTeal
    case "blue": .categoryBlue
    case "cyan": .categoryCyan
    default: .brand
    }
  }

  /// What to call a category on screen.
  ///
  /// A category seeded by the core carries an English name, because a
  /// database cannot hold one name per language and storing a translated
  /// one would freeze whichever language happened to be on the day it was
  /// created. So a built-in whose name is still the one it was seeded with
  /// is shown translated, and the moment somebody renames it their name is
  /// the answer and no translation second-guesses it.
  /// Takes the two fields it reads rather than a whole category, so the
  /// rule can be exercised without building one.
  static func name(_ stored: String, iconKey: String?) -> String {
    guard let iconKey, stored == seededName(iconKey) else { return stored }
    return translated(iconKey)
  }

  /// The English name the migration gives a built-in category.
  ///
  /// Kept in step with `003-seed-categories.sql` by a test, since a
  /// rename there would silently stop this side translating anything.
  static func seededName(_ iconKey: String) -> String? {
    switch iconKey {
    case "video": "Video"
    case "music": "Music"
    case "reading": "Reading"
    case "games": "Games"
    case "tools": "Tools"
    case "ai": "AI"
    case "dev": "Dev"
    case "storage": "Storage"
    default: nil
    }
  }

  /// The translated name for a built-in, from the catalogue.
  ///
  /// Written out one key at a time rather than looked up by interpolation,
  /// because a key assembled at runtime never reaches the catalogue: only
  /// literals are extracted.
  private static func translated(_ iconKey: String) -> String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch iconKey {
    case "video": String(localized: "Video", bundle: bundle, locale: locale,
                         comment: "Built-in category for streaming and film")
    case "music": String(localized: "Music", bundle: bundle, locale: locale,
                         comment: "Built-in category")
    case "reading": String(localized: "Reading", bundle: bundle, locale: locale,
                           comment: "Built-in category for books and articles")
    case "games": String(localized: "Games", bundle: bundle, locale: locale,
                         comment: "Built-in category")
    case "tools": String(localized: "Tools", bundle: bundle, locale: locale,
                         comment: "Built-in category for utilities and productivity")
    case "ai": String(localized: "AI", bundle: bundle, locale: locale,
                      comment: "Built-in category for AI assistants")
    case "dev": String(localized: "Dev", bundle: bundle, locale: locale,
                       comment: "Built-in category for developer tools")
    case "storage": String(localized: "Storage", bundle: bundle, locale: locale,
                           comment: "Built-in category for cloud storage")
    default: iconKey
    }
  }
}
