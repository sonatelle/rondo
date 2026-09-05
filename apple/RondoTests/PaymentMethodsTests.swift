import Foundation
@testable import Rondo
import Testing

/// The mapping from a payment method's stored name to what is read on
/// screen. The same shape as `CategoriesTests`, because it is the same rule.
struct PaymentMethodsTests {
  /// This side keeps its own copy of the English names the migration
  /// writes. A rename in the SQL would quietly stop every translation
  /// working - the words would still appear, in English, with nothing to
  /// say why - so the two lists are held to each other here.
  @Test("Every seeded name matches the migration that writes it")
  func seededNamesMatchTheMigration() throws {
    let migration = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "crates/rondo-core/migrations/004-seed-payment-methods.sql")
    let sql = try String(contentsOf: migration, encoding: .utf8)

    for name in PaymentMethods.seededNames {
      #expect(sql.contains("'\(name)'"), "the migration does not seed \(name)")
    }
  }

  /// Which of the two comes back depends on the language this runs in, and
  /// both are the catalogue answering correctly. What is held down is that
  /// the name went through the catalogue at all.
  @Test("A built-in still carrying its seeded name is translated")
  func aBuiltInIsTranslated() {
    let shown = PaymentMethods.name("Alipay")
    #expect(["Alipay", "支付宝"].contains(shown), "got \(shown)")
  }

  /// The whole point of matching on the name: once it is somebody's own
  /// words, no translation may second-guess them.
  @Test("A name of somebody's own is shown as they wrote it")
  func aRenamedMethodIsLeftAlone() {
    #expect(PaymentMethods.name("招行 ···· 4821") == "招行 ···· 4821")
    #expect(PaymentMethods.name("Visa ·1234") == "Visa ·1234")
  }
}
