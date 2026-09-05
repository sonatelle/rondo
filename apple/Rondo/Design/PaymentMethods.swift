import Foundation

/// What to call a payment method on screen.
///
/// The same rule as `Categories.name`, and for the same reason: a database
/// cannot hold one name per language, so the migration seeds English names
/// and a built-in still carrying the one it was given is shown translated.
/// Rename it and the stored name is the answer - somebody who calls a card
/// "招行 ···· 4821" means that, in any language.
///
/// There is no icon or colour here. A payment method is a name and an
/// order; the core deliberately holds nothing else about it.
enum PaymentMethods {
  /// The English names `004-seed-payment-methods.sql` gives the built-ins.
  ///
  /// Kept in step with the migration by a test, since a rename there would
  /// silently stop this side translating anything.
  static let seededNames = ["Gift card", "WeChat", "Alipay", "Bank card"]

  static func name(_ stored: String) -> String {
    guard seededNames.contains(stored) else { return stored }
    return translated(stored)
  }

  /// Written out one key at a time rather than looked up by interpolation:
  /// only literals are extracted into the catalogue.
  private static func translated(_ stored: String) -> String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch stored {
    case "Gift card": String(localized: "Gift card", bundle: bundle, locale: locale,
                             comment: "Built-in payment method")
    case "WeChat": String(localized: "WeChat", bundle: bundle, locale: locale,
                          comment: "Built-in payment method: paying through WeChat")
    case "Alipay": String(localized: "Alipay", bundle: bundle, locale: locale,
                          comment: "Built-in payment method")
    case "Bank card": String(localized: "Bank card", bundle: bundle, locale: locale,
                             comment: "Built-in payment method: a debit or credit card")
    default: stored
    }
  }
}
