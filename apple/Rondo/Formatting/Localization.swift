import Foundation

/// Which language the interface is written in, and where its words come
/// from.
///
/// Rondo lets someone choose a language rather than only following the
/// system, because a Mac set to one language is not a promise about which
/// language its owner reads an app in. That choice cannot be made through
/// SwiftUI's environment: `Text` resolves a key against `Bundle.main` and
/// the system's language, so every call site passes `Localization.bundle`
/// instead. A test enforces that, since a forgotten `bundle:` is invisible
/// - the string simply follows the system and nobody notices until they
/// switch languages.
enum Localization {
  /// The languages this build can show, taken from the bundle itself.
  ///
  /// Derived rather than listed, so adding a language to the string
  /// catalogue makes it appear in the picker without touching any Swift.
  /// "Base" is not a language; it is where the development strings live.
  static var available: [String] {
    Bundle.main.localizations
      .filter { $0 != "Base" }
      .sorted()
  }

  /// The language actually in use: the stored choice when it is one this
  /// build has, and otherwise whichever of ours the system prefers.
  static var resolved: String {
    resolved(UserDefaults.standard.string(forKey: Preference.appLanguage) ?? "")
  }

  /// The same, for a choice handed in rather than read.
  ///
  /// SwiftUI only rebuilds what it has seen a view read. A scene that set
  /// its locale from the stored value directly never registered a
  /// dependency on the preference, so picking a language did nothing until
  /// the next launch; passing the value through makes the dependency
  /// something SwiftUI can see.
  static func resolved(_ choice: String) -> String {
    if !choice.isEmpty, available.contains(choice) {
      return choice
    }
    return systemPreferred
  }

  /// Whichever language this build has that the system asks for first.
  ///
  /// `Bundle.preferredLocalizations` does the matching macOS itself would
  /// do, including falling back from a regional variant to its base.
  static var systemPreferred: String {
    Bundle.preferredLocalizations(
      from: available,
      forPreferences: Locale.preferredLanguages
    ).first ?? "en"
  }

  /// The bundle to read words from.
  ///
  /// Cached: this is asked for by every piece of text on screen, and
  /// resolving it touches the file system.
  static var bundle: Bundle {
    Cache.bundle(for: resolved)
  }

  /// The locale to lay out dates, numbers and lists in.
  ///
  /// Built from the resolved language rather than from `Locale.current`,
  /// so a sentence cannot be half one language and half another. Read
  /// straight from the region, an English interface on a Chinese Mac
  /// joined English clauses with a Chinese conjunction and dated them in
  /// Chinese.
  static var locale: Locale {
    Locale(identifier: resolved)
  }

  /// The locale for a choice handed in; see `resolved(_:)`.
  static func locale(for choice: String) -> Locale {
    Locale(identifier: resolved(choice))
  }

  /// A language's name, written in that language.
  ///
  /// The identifier form rather than the language-code form: it is what
  /// tells 简体中文 from 繁體中文, which the code form flattens to one name.
  static func displayName(of code: String) -> String {
    Locale(identifier: code).localizedString(forIdentifier: code) ?? code
  }

  /// Resolved bundles, kept so the file system is only asked once.
  ///
  /// Behind a lock rather than isolated to an actor: text is drawn on the
  /// main thread, but `Formatting` is also called from tests, and an
  /// isolation that only holds sometimes is no isolation at all.
  private enum Cache {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var bundles: [String: Bundle] = [:]

    static func bundle(for language: String) -> Bundle {
      lock.lock()
      let cached = bundles[language]
      lock.unlock()
      if let cached {
        return cached
      }

      let resolved = resolve(language)
      lock.lock()
      bundles[language] = resolved
      lock.unlock()
      return resolved
    }

    /// Falls back to the whole bundle rather than failing: a missing
    /// `.lproj` should cost the words their translation, not the screen.
    private static func resolve(_ language: String) -> Bundle {
      guard
        let path = Bundle.main.path(forResource: language, ofType: "lproj"),
        let bundle = Bundle(path: path)
      else {
        return .main
      }
      return bundle
    }
  }
}
