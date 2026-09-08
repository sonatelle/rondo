import Foundation
import Testing

@testable import Rondo

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
      .map { (name: $0.lastPathComponent, text: try String(contentsOf: $0, encoding: .utf8)) }
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
