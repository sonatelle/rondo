import Foundation
import Testing

/// Tests that every word on screen is read from the chosen language.
///
/// `Localization` explains the rule: a `LocalizedStringKey` handed to
/// `Text`, `Button`, `Label` and their like is resolved against
/// `Bundle.main` and the *system's* language, so it ignores the language
/// somebody picked in settings. Words have to be looked up with
/// `Localization.bundle` and arrive at the view as text to draw.
///
/// Breaking that rule costs nothing at build time and nothing at runtime on
/// a Mac whose language matches: it shows up only when the two differ, and
/// only to whoever is reading the wrong one. So it is checked here, by
/// reading the sources the way `CatalogueTests` reads the catalogue.
struct SourceLanguageTests {
  /// The app's own Swift, found from this file rather than from a bundle:
  /// source is not something a test bundle carries.
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

  /// The initialisers that take a `LocalizedStringKey`, written with a
  /// literal in front of them.
  ///
  /// Matching the literal is what makes this precise: `Text(someString)` is
  /// the verbatim initialiser and is fine, while `Text("...")` is a key.
  /// The list is the constructors this app actually reaches for; a new one
  /// joins it the first time somebody uses it.
  private static let keyTakers = [
    "Text", "Button", "Label", "Toggle", "Picker", "Menu", "Section",
    "TextField", "Stepper", "LabeledContent", "TableColumn", "CommandMenu",
    "ContentUnavailableView",
  ]

  @Test("No word on screen is left to the system's language")
  func everyStringIsLookedUp() throws {
    // `Text(verbatim: "...")` is text to draw rather than a key to resolve,
    // and it is how a looked-up string reaches the screen.
    let verbatim = #/\bText\(\s*verbatim:/#
    let offenders = try sources().flatMap { file -> [String] in
      // The comments in these files quote the very shapes being banned.
      let code = file.text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
      return Self.keyTakers.flatMap { taker -> [String] in
        let call = try! Regex("\\b\(taker)\\(\\s*\"")
        return code.matches(of: call).compactMap { match in
          guard code[match.range].matches(of: verbatim).isEmpty else { return nil }
          let line = code[code.startIndex ..< match.range.lowerBound]
            .count(where: { $0 == "\n" }) + 1
          return "\(file.name):\(line) \(taker)(\"…\")"
        }
      }
    }
    #expect(
      offenders.isEmpty,
      """
      These pass a key rather than a looked-up string, so they follow the \
      Mac's language instead of the chosen one. Use \
      String(localized:bundle:locale:comment:) with Localization.bundle: \
      \(offenders.sorted())
      """
    )
  }

  @Test("Nothing looks a word up in the wrong bundle")
  func everyLookupNamesTheBundle() throws {
    // `String(localized:)` without a bundle reads `Bundle.main` and the
    // system's language, which is the same bug wearing a different hat.
    let lookup = #/String\(\s*\n?\s*localized:/#
    let offenders = try sources().flatMap { file -> [String] in
      file.text.matches(of: lookup).compactMap { match in
        // The bundle may be named a few lines down, so look at the call
        // rather than the line it starts on.
        let tail = file.text[match.range.lowerBound...].prefix(400)
        guard !tail.contains("bundle:") else { return nil }
        let line = file.text[file.text.startIndex ..< match.range.lowerBound]
          .count(where: { $0 == "\n" }) + 1
        return "\(file.name):\(line)"
      }
    }
    #expect(
      offenders.isEmpty,
      "String(localized:) with no bundle: reads the system's language: \(offenders.sorted())"
    )
  }
}
