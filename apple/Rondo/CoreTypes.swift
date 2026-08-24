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
  var cycleDescription: String {
    let count = Int(subscription.cycleCount)
    guard count != 1 else {
      return switch subscription.cycleUnit {
      case .day: "Daily"
      case .week: "Weekly"
      case .month: "Monthly"
      case .year: "Yearly"
      }
    }
    let unit =
      switch subscription.cycleUnit {
      case .day: "days"
      case .week: "weeks"
      case .month: "months"
      case .year: "years"
      }
    return "Every \(count) \(unit)"
  }
}
