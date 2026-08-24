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
