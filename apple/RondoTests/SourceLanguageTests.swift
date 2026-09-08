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

  @Test("Every word the code asks for is in the catalogue")
  func everyKeyIsInTheCatalogue() throws {
    // A key the catalogue has never heard of does not fail to build and
    // does not fail to run: the lookup falls back to the key itself, so an
    // English word appears in a Chinese window and only a reader of that
    // language ever finds out. "Total" reached a table heading that way.
    //
    // `CatalogueTests` checks the other direction - that everything in the
    // catalogue is translated - and the two together are what say the
    // screen has no English left on it.
    let catalogue = try catalogueKeys()
    let lookup = #/String\(\s*\n?\s*localized:\s*\n?\s*"([^"\\]*)"/#
    let offenders = try sources().flatMap { file -> [String] in
      file.text.matches(of: lookup).compactMap { match in
        let key = String(match.output.1)
        // A key with a value in it - "About \(levelled) a month" - reaches
        // the catalogue with a format specifier in place of the value, and
        // which specifier depends on the type. Those are left to the
        // export; what is checked here is every plain word.
        guard !key.isEmpty, !catalogue.contains(key) else { return nil }
        let line = file.text[file.text.startIndex ..< match.range.lowerBound]
          .count(where: { $0 == "\n" }) + 1
        return "\(file.name):\(line) \(key.debugDescription)"
      }
    }
    #expect(
      offenders.isEmpty,
      "asked for but not in the catalogue, so they stay English: \(offenders.sorted())"
    )
  }

  @Test("Every phrase with a value in it reaches the catalogue too")
  func everyInterpolatedKeyIsInTheCatalogue() throws {
    // The check above cannot see these. Its pattern wants a closing quote
    // straight after the words, and an interpolated string has a backslash
    // there instead, so `String(localized: "including \(codes)")` matches
    // nothing and passes silently. Two footnotes were added that way and
    // went untranslated with every test green.
    //
    // Matching them exactly would mean knowing which specifier each value
    // becomes - `%@` for a string, `%lld` for an integer - which is type
    // information a text scan does not have. So this asks something
    // weaker and still useful: the longest run of actual words in the
    // phrase has to appear in *some* catalogue key. A new phrase nobody
    // translated has no such key; a translated one does.
    let catalogue = try catalogueKeys()
    let opening = #/String\(\s*\n?\s*localized:\s*\n?\s*"/#

    var offenders: [String] = []
    for file in try sources() {
      for match in file.text.matches(of: opening) {
        let runs = Self.literalRuns(in: file.text, after: match.range.upperBound)
        // Only phrases with a value in them; the plain ones are the check
        // above's business and it is exact where this is not.
        guard runs.count > 1 else { continue }

        // Three characters is the floor: a shorter run - " at ", " · " -
        // turns up inside some unrelated key and would let this pass on
        // anything.
        guard let longest = runs
          .filter({ $0.count >= 3 })
          .max(by: { $0.count < $1.count })
        else { continue }

        if !catalogue.contains(where: { $0.contains(longest) }) {
          let line = file.text[file.text.startIndex ..< match.range.lowerBound]
            .count(where: { $0 == "\n" }) + 1
          offenders.append("\(file.name):\(line) \(longest.debugDescription)")
        }
      }
    }
    #expect(
      offenders.isEmpty,
      "no catalogue key carries these words, so they stay English: \(offenders.sorted())"
    )
  }

  /// The runs of plain text in the Swift string literal starting at `start`,
  /// which is just past its opening quote.
  ///
  /// Walked rather than matched with a pattern. An interpolation carries
  /// its own parentheses and its own quoted strings - `\(a.joined(
  /// separator: ", "))` has both - and a regex that tries to step over one
  /// either stops early or swallows the rest of the line. Getting this
  /// wrong is not harmless: the first attempt reported eight phrases that
  /// were translated all along, and a check that cries wolf teaches
  /// everyone to skip it.
  private static func literalRuns(in text: String, after start: String.Index) -> [String] {
    var runs: [String] = []
    var current = ""
    var index = start
    var depth = 0

    while index < text.endIndex {
      let character = text[index]
      if depth == 0 {
        if character == "\"" { break }
        if character == "\\", text.index(after: index) < text.endIndex,
           text[text.index(after: index)] == "("
        {
          runs.append(current)
          current = ""
          depth = 1
          index = text.index(index, offsetBy: 2)
          continue
        }
        current.append(character)
      } else {
        // Inside the value. Quotes here belong to it, not to the phrase.
        if character == "(" { depth += 1 }
        if character == ")" { depth -= 1 }
      }
      index = text.index(after: index)
    }
    runs.append(current)
    return runs
  }

  /// The keys the catalogue carries, read as a document the way
  /// `CatalogueTests` reads it.
  private func catalogueKeys() throws -> Set<String> {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Rondo/Resources/Localizable.xcstrings")
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = try #require(root?["strings"] as? [String: Any])
    return Set(strings.keys)
  }
}
