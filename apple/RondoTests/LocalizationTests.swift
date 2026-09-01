import Foundation
import Testing

@testable import Rondo

/// Tests for how the interface's language is chosen.
struct LocalizationTests {
  @Test("The languages offered come from the bundle, not from a list in code")
  func availableComesFromTheBundle() {
    // The point of deriving them: adding a language to the catalogue must
    // make it appear without anyone editing Swift. If this ever became a
    // hard-coded array, the two could disagree and only the picker would
    // be wrong.
    #expect(Localization.available == Bundle.main.localizations.filter { $0 != "Base" }.sorted())
    #expect(Localization.available.contains("en"))
    #expect(!Localization.available.contains("Base"))
  }

  @Test("A stored language this build does not have is ignored")
  func unknownChoiceFallsBack() {
    let defaults = UserDefaults.standard
    let previous = defaults.string(forKey: Preference.appLanguage)
    defer { defaults.set(previous, forKey: Preference.appLanguage) }

    // A catalogue can lose a language between releases, and the stored
    // choice outlives it. Honouring it would leave the app looking for an
    // .lproj that is not there.
    defaults.set("xx-Klingon", forKey: Preference.appLanguage)
    #expect(Localization.resolved == Localization.systemPreferred)
    #expect(Localization.available.contains(Localization.resolved))
  }

  @Test("An empty choice means following the system")
  func emptyChoiceFollowsTheSystem() {
    let defaults = UserDefaults.standard
    let previous = defaults.string(forKey: Preference.appLanguage)
    defer { defaults.set(previous, forKey: Preference.appLanguage) }

    defaults.set("", forKey: Preference.appLanguage)
    #expect(Localization.resolved == Localization.systemPreferred)
  }

  @Test("A language this build has is honoured")
  func knownChoiceWins() {
    let defaults = UserDefaults.standard
    let previous = defaults.string(forKey: Preference.appLanguage)
    defer { defaults.set(previous, forKey: Preference.appLanguage) }

    defaults.set("en", forKey: Preference.appLanguage)
    #expect(Localization.resolved == "en")
    #expect(Localization.locale.identifier == "en")
  }

  @Test("Languages are named in their own words")
  func namesAreAutonyms() {
    // A picker that says "Chinese" to someone who reads Chinese is asking
    // them to read the language they are trying to switch away from.
    #expect(Localization.displayName(of: "en") == "English")
    #expect(Localization.displayName(of: "zh-Hans") == "简体中文")
    // Distinguishing the two scripts matters; the language-code form calls
    // both of them 中文.
    #expect(Localization.displayName(of: "zh-Hant") != Localization.displayName(of: "zh-Hans"))
  }

  @Test("The bundle resolves, and resolves to the same one twice")
  func bundleIsResolvedAndCached() {
    let defaults = UserDefaults.standard
    let previous = defaults.string(forKey: Preference.appLanguage)
    defer { defaults.set(previous, forKey: Preference.appLanguage) }

    defaults.set("zh-Hans", forKey: Preference.appLanguage)
    let first = Localization.bundle
    let second = Localization.bundle
    #expect(first === second)
    #expect(first.bundleURL.lastPathComponent == "zh-Hans.lproj")
  }

  @Test("A word is read from the chosen language, not the system's")
  func wordsFollowTheChoice() {
    // The whole point of the layer. "Reminders" is in the catalogue with a
    // Chinese translation, so the two bundles must answer differently.
    let english = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
    let chinese = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj").flatMap(Bundle.init(path:))
    let chineseWord = chinese?.localizedString(forKey: "Reminders", value: nil, table: nil)
    #expect(chineseWord == "提醒")
    // English has no .lproj of its own: it is the development language, so
    // the key is the word.
    #expect(english == nil || english?.localizedString(forKey: "Reminders", value: nil, table: nil) == "Reminders")
  }
}
