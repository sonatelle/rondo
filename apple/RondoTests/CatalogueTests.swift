import Foundation
@testable import Rondo
import Testing

/// Tests for the string catalogue as a document.
///
/// These read the catalogue rather than the app, because what they catch -
/// a language left half-translated, a comma of the wrong width - is
/// invisible at runtime to anyone who does not read that language.
struct CatalogueTests {
  /// The catalogue as it sits in the source tree.
  ///
  /// Found from this file's own path rather than from the bundle: Xcode
  /// compiles an `.xcstrings` into per-language `.strings`, so the
  /// document these tests are about never reaches a bundle at all.
  private func catalogue() throws -> [String: [String: String]] {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Rondo/Localizable.xcstrings")
    try #require(
      FileManager.default.fileExists(atPath: url.path),
      "no catalogue at \(url.path)"
    )
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = try #require(root?["strings"] as? [String: Any])

    var byKey: [String: [String: String]] = [:]
    for (key, entry) in strings {
      guard
        let entry = entry as? [String: Any],
        let localizations = entry["localizations"] as? [String: Any]
      else {
        byKey[key] = [:]
        continue
      }
      var values: [String: String] = [:]
      for (language, payload) in localizations {
        guard let payload = payload as? [String: Any] else { continue }
        if let unit = payload["stringUnit"] as? [String: Any],
           let value = unit["value"] as? String
        {
          values[language] = value
        } else if let variations = payload["variations"] as? [String: Any],
                  let plural = variations["plural"] as? [String: Any]
        {
          // A plural entry has no single value; keep the "other" form,
          // which is the one every language has.
          if let other = plural["other"] as? [String: Any],
             let unit = other["stringUnit"] as? [String: Any],
             let value = unit["value"] as? String
          {
            values[language] = value
          }
        }
      }
      byKey[key] = values
    }
    return byKey
  }

  @Test("Every language the app offers translates every string")
  func noLanguageIsHalfDone() throws {
    let catalogue = try catalogue()
    // English is the source language: its words are the keys, so it has no
    // entries of its own and needs none.
    let translated = Localization.available.filter { $0 != "en" }

    for language in translated {
      let missing = catalogue.filter { $0.value[language] == nil }.keys.sorted()
      #expect(
        missing.isEmpty,
        "\(language) is missing \(missing.count) of \(catalogue.count): \(missing.prefix(5))"
      )
    }
  }

  @Test("Chinese sentences use Chinese punctuation")
  func chinesePunctuationIsFullWidth() throws {
    // A half-width comma between Chinese characters is the wrong glyph
    // rather than a matter of taste: it sits on the baseline and carries
    // no trailing space, where the language expects a wide mark that does.
    let offenders = try catalogue().compactMap { key, values -> String? in
      guard let zh = values["zh-Hans"] else { return nil }
      let wrong = #/[\x{4E00}-\x{9FFF}][,?!;:]|[,?!;:][\x{4E00}-\x{9FFF}]/#
      return zh.contains(wrong) ? "\(key) -> \(zh)" : nil
    }
    #expect(offenders.isEmpty, "half-width punctuation in Chinese: \(offenders)")
  }

  @Test("A format specifier survives translation")
  func placeholdersAreKept() throws {
    // A translation that drops a "%lld" does not fail to build; it fails
    // at the moment someone reads it, with a number missing from a
    // sentence about their money.
    let specifier = #/%(?:lld|llu|@|d|u)/#
    for (key, values) in try catalogue() {
      let inKey = key.matches(of: specifier).count
      guard inKey > 0 else { continue }
      for (language, value) in values {
        #expect(
          value.matches(of: specifier).count == inKey,
          "\(language) changed the placeholders of \(key.debugDescription): \(value)"
        )
      }
    }
  }
}

/// Only here to name this bundle for `Bundle(for:)`.
private final class BundleToken {}
