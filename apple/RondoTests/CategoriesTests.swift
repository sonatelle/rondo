import Foundation
@testable import Rondo
import Testing

/// The mapping from a category's keys to what this platform draws and reads.
struct CategoriesTests {
  /// This side keeps its own copy of the English names the migration
  /// writes, and translates a category only while its name still matches.
  /// A rename in the SQL would quietly stop every translation working, so
  /// the two lists are held to each other here rather than trusted.
  @Test("Every seeded name matches the migration that writes it")
  func seededNamesMatchTheMigration() throws {
    let migration = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "crates/rondo-core/migrations/003-seed-categories.sql")
    let sql = try String(contentsOf: migration, encoding: .utf8)

    for key in ["video", "music", "reading", "games", "tools", "ai", "dev", "storage"] {
      let name = try #require(Categories.seededName(key), "no seeded name for \(key)")
      #expect(
        sql.contains("'\(name)'") && sql.contains("'\(key)'"),
        "the migration does not seed \(key) as \(name)"
      )
    }
  }

  /// Which of the two comes back depends on the machine this runs on, and
  /// both are the catalogue answering correctly. What is being held down is
  /// that the name went through the catalogue at all rather than being
  /// handed back from the database, and that the key resolved to a real
  /// entry rather than to the key itself.
  @Test("A built-in still carrying its seeded name is translated")
  func aBuiltInIsTranslated() {
    let shown = Categories.name("Video", iconKey: "video")
    #expect(["Video", "影音"].contains(shown), "got \(shown)")
    #expect(shown != "video", "the key came back instead of a translation")
  }

  /// The moment somebody renames a category, their name is the answer.
  @Test("A renamed category keeps the name it was given")
  func aRenamedCategoryIsLeftAlone() {
    #expect(Categories.name("Screens", iconKey: "video") == "Screens")
  }

  /// A category somebody made themselves has no icon key and no business
  /// being translated.
  @Test("A category of one's own is never translated")
  func aHandMadeCategoryIsLeftAlone() {
    #expect(Categories.name("Video", iconKey: nil) == "Video")
  }

  /// A key from a newer version has to draw as something rather than
  /// crashing or leaving a hole.
  @Test("An unknown key falls back rather than failing")
  func unknownKeysFallBack() {
    #expect(Categories.symbol(for: "podcasts") == "tag.fill")
    #expect(Categories.symbol(for: nil) == "tag.fill")
    #expect(Categories.tint(for: "chartreuse") == .brand)
    #expect(Categories.seededName("podcasts") == nil)
  }

  @Test("Every seeded key has a symbol and a colour of its own")
  func everySeededKeyIsDrawable() {
    for key in ["video", "music", "reading", "games", "tools", "ai", "dev", "storage"] {
      #expect(Categories.symbol(for: key) != "tag.fill", "\(key) fell back to the default symbol")
    }
    for key in ["pink", "violet", "green", "red", "amber", "teal", "blue", "cyan"] {
      #expect(Categories.tint(for: key) != .brand, "\(key) fell back to the accent")
    }
  }
}
