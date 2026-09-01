import SwiftUI

/// Which subscriptions the window is showing.
///
/// The sidebar picks one of these. The core answers with everything or
/// with the active ones, so narrowing to just the archived is done here -
/// it is a question about what to display, not a rule about billing.
enum SubscriptionFilter: String, CaseIterable, Identifiable {
  case active
  case archived
  case all

  var id: String {
    rawValue
  }

  /// A key rather than a `String`: `Label` and `navigationTitle` take a
  /// `LocalizedStringKey`, so this is looked up rather than shown as it
  /// is written here.
  var title: LocalizedStringKey {
    switch self {
    case .active: "Active"
    case .archived: "Archived"
    case .all: "All"
    }
  }

  var symbol: String {
    switch self {
    case .active: "repeat"
    case .archived: "archivebox"
    case .all: "tray.full"
    }
  }

  /// Keeps only what this filter names, once the core has answered.
  func matches(_ renewal: Renewal) -> Bool {
    switch self {
    case .active: renewal.subscription.status == .active
    case .archived: renewal.subscription.status == .archived
    case .all: true
    }
  }
}
