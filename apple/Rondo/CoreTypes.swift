import Foundation

// SwiftUI conformances for the generated core types.
//
// The bindings are compiled into this target and regenerated on every
// packaging run, so nothing may be added to them by hand. Conformances
// that only SwiftUI needs live here instead, where they survive.

extension Subscription: Identifiable {
  // `id` is already the core's stable UUIDv7; SwiftUI only needs to be
  // told that it is the identity.
}

extension Renewal: Identifiable {
  /// A renewal is identified by its subscription: the pairing is derived
  /// from a reference date, so the subscription is the part that persists.
  /// Public because `Renewal` is, and a conformance cannot be narrower
  /// than the type it is on.
  public var id: Uuid {
    subscription.id
  }
}

extension Renewal {
  /// The price as a number, for sorting a column by it.
  ///
  /// Sorting the string itself would put "9.99" after "15.90", since that
  /// is the order those characters come in.
  var amountValue: Decimal {
    Formatting.decimal(subscription.amount) ?? 0
  }

  /// Roughly how many days the cycle spans, for ordering by how often a
  /// subscription is charged.
  ///
  /// Approximate on purpose: this only ranks cycles against each other,
  /// and the core owns every figure that has to be exact.
  var cycleDays: Int {
    let unit =
      switch subscription.cycleUnit {
      case .day: 1
      case .week: 7
      case .month: 30
      case .year: 365
      }
    return Int(subscription.cycleCount) * unit
  }

  /// How the cycle reads in a column: "Monthly", "Every 3 months".
  ///
  /// Asked for whole rather than assembled from a number and a unit. Built
  /// by joining, as this once was, the phrase can only ever be English: a
  /// language that puts the count elsewhere, or inflects the noun, has
  /// nowhere to say so.
  var cycleDescription: String {
    let count = Int(subscription.cycleCount)
    let bundle = Localization.bundle
    let locale = Localization.locale
    guard count != 1 else {
      return switch subscription.cycleUnit {
      case .day: String(localized: "Daily", bundle: bundle, locale: locale)
      case .week: String(localized: "Weekly", bundle: bundle, locale: locale)
      case .month: String(localized: "Monthly", bundle: bundle, locale: locale)
      case .year: String(localized: "Yearly", bundle: bundle, locale: locale)
      }
    }
    return switch subscription.cycleUnit {
    case .day: String(localized: "Every \(count) days", bundle: bundle, locale: locale)
    case .week: String(localized: "Every \(count) weeks", bundle: bundle, locale: locale)
    case .month: String(localized: "Every \(count) months", bundle: bundle, locale: locale)
    case .year: String(localized: "Every \(count) years", bundle: bundle, locale: locale)
    }
  }
}
