import Foundation

/// How the full list is arranged: as one table, or gathered into groups.
///
/// The dimensions are the fields a subscription is filed under, and each
/// answers a question the flat table cannot. "How much is on that card"
/// is the one the design names, and it is the same shape of question as
/// "how much goes on streaming" or "how much is in dollars".
enum Grouping: String, CaseIterable, Identifiable {
  case none
  case category
  case channel
  case paymentMethod
  case currency

  var id: String {
    rawValue
  }

  /// A key, for the same reason as `Navigation.title`.
  var title: String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch self {
    case .none:
      String(localized: "No grouping", bundle: bundle, locale: locale,
             comment: "The list as one flat table")
    case .category:
      String(localized: "By category", bundle: bundle, locale: locale,
             comment: "Analytics card: what kind of thing the money goes on")
    case .channel:
      String(localized: "By where it was bought", bundle: bundle, locale: locale,
             comment: "Groups the list by channel")
    case .paymentMethod:
      String(localized: "By payment method", bundle: bundle, locale: locale,
             comment: "Groups the list by what pays for each subscription")
    case .currency:
      String(localized: "By currency", bundle: bundle, locale: locale,
             comment: "Groups the list by the currency each is billed in")
    }
  }

  /// What a subscription is filed under, as a key that sorts.
  ///
  /// `nil` gathers everything nobody has filled the field in for. Kept as
  /// its own group rather than hidden, so the groups add up to the list.
  func key(of subscription: Subscription) -> String? {
    switch self {
    case .none: nil
    case .category: subscription.categoryId
    case .channel: subscription.channel.map { "\($0)" }
    case .paymentMethod: subscription.paymentMethodId
    case .currency: subscription.currency
    }
  }
}
