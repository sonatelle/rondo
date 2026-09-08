import Foundation
@testable import Rondo
import Testing

/// Tests that the model reaches the views the only way this app supplies it.
///
/// Every view here is handed `SubscriptionsModel` explicitly, as a `let`.
/// Nothing ever calls `.environment(model)`, so a view asking the
/// environment for one gets nothing - and `@Environment(SubscriptionsModel
/// .self)` traps rather than returning nil when nothing supplies it.
///
/// That is a crash with no compile error and no warning, on the first click
/// that reaches the view. It happened: the currency settings tab was
/// written that way and took the app down the moment it was opened, because
/// the settings scene is separate from the window scene and was never given
/// a model. Nothing in the suite caught it, because a test can build a view
/// value without ever resolving its environment.
///
/// So the rule is checked in the source, the way `SourceLanguageTests`
/// checks the language rule: cheap, and it fails at the right moment.
struct ModelWiringTests {
  /// The app's own Swift, found from this file rather than from a bundle.
  private func sources() throws -> [(name: String, text: String)] {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Rondo")
    let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
      .compactMap { $0 as? URL }
      .filter { $0.pathExtension == "swift" } ?? []
    try #require(!files.isEmpty, "no Swift sources under \(root.path)")
    return try files
      .sorted { $0.path < $1.path }
      .map { try (name: $0.lastPathComponent, text: String(contentsOf: $0, encoding: .utf8)) }
  }

  @Test("No view reaches for the model through the environment")
  func modelIsNeverTakenFromTheEnvironment() throws {
    var offenders: [String] = []
    for file in try sources() {
      for (number, line) in file.text.components(separatedBy: .newlines).enumerated() {
        let code = line.trimmingCharacters(in: .whitespaces)
        // Comments are skipped, or this rule flags the paragraph above
        // that explains it - which it did, the first time it was run.
        guard !code.hasPrefix("//") else { continue }
        if code.contains("@Environment(SubscriptionsModel.self)") {
          offenders.append("\(file.name):\(number + 1)")
        }
      }
    }
    #expect(
      offenders.isEmpty,
      """
      These read SubscriptionsModel from the environment, which nothing in \
      this app puts there - the view will trap when it is first shown. \
      Pass the model in as a `let` instead: \(offenders)
      """
    )
  }

  @Test("No view reads the primary currency behind SwiftUI's back")
  func primaryCurrencyIsReadFromTheModel() throws {
    // `Currencies.preferred` reads `UserDefaults` directly, so a view that
    // calls it gives SwiftUI nothing to notice when the setting changes.
    // Rates on screen went on saying "USD" after the setting had moved to
    // CNY, and only a row that happened to be newly created came out
    // right - which is what made it look like a refresh problem rather
    // than a missing dependency. It took three attempts to see that.
    //
    // `model.primaryCurrency` is the same value as observable state.
    //
    // Two files are allowed it and say why in place: the model, which is
    // where the preference is read, and the form, which uses it once as
    // the initial value of a field rather than as something to redraw for.
    let allowed = ["SubscriptionsModel.swift", "SubscriptionFormView.swift",
                   "Currency.swift", "CurrencySettings.swift"]
    var offenders: [String] = []
    for file in try sources() where !allowed.contains(file.name) {
      for (number, line) in file.text.components(separatedBy: .newlines).enumerated() {
        let code = line.trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix("//") else { continue }
        if code.contains("Currencies.preferred") {
          offenders.append("\(file.name):\(number + 1)")
        }
      }
    }
    #expect(
      offenders.isEmpty,
      """
      These read the primary currency from the defaults, which SwiftUI \
      cannot track - the view will keep showing the old one. Use \
      model.primaryCurrency: \(offenders)
      """
    )
  }

  @Test("Every rate-derived query takes an observable dependency")
  func rateQueriesRegisterWithSwiftUI() throws {
    // The other half of the same bug. These three ask the database a
    // question, and a question is not a dependency: a fetch landing a
    // second after a view drew changed nothing on screen, so switching to
    // a currency never seen before left every field blank underneath a
    // note saying the rates had just been updated.
    //
    // Each reads `ratesVersion` first, which is what the calling body ends
    // up depending on. Nothing enforces that at compile time, and removing
    // a line would pass every other test here - hence this one.
    let model = try String(
      contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Rondo/Model/SubscriptionsModel.swift"),
      encoding: .utf8
    )
    for query in ["func converted(", "func rates(for", "func pairRate("] {
      let start = try #require(model.range(of: query), "\(query) has been renamed")
      let body = model[start.lowerBound...].prefix(600)
      #expect(
        body.contains("ratesVersion"),
        "\(query) does not read ratesVersion, so a view calling it will not redraw when rates change"
      )
    }
  }

  @Test("Settings opens even when the database did not")
  @MainActor
  func settingsSurvivesAFailedDatabase() {
    // The currency tab is the only one that needs a model, and somebody
    // whose database failed may well be opening settings to find out where
    // the file is. Building it with nothing must not trap.
    _ = SettingsView(model: nil)
    _ = CurrencySettings(model: nil)
  }
}
