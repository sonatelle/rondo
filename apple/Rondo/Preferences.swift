import ServiceManagement
import SwiftUI

/// The keys the app stores its preferences under.
///
/// Gathered here because several of them are read from more than one place
/// - the delegate that decides whether closing the window quits also needs
/// the one that says whether there is a menu bar item to fall back to - and
/// a key spelled differently in two files is a preference that silently
/// stops working.
enum Preference {
  static let appearance = "appearance"
  static let showsMenuBarItem = "showsMenuBarItem"
  static let quitsOnWindowClose = "quitsOnWindowClose"
  static let primaryCurrency = "primaryCurrency"
  /// A weekday index in `Calendar`'s numbering, where Sunday is 1.
  static let firstWeekday = "firstWeekday"
}

/// Which appearance the person asked for.
enum Appearance: String, CaseIterable, Identifiable {
  case light
  case dark
  case system

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .light: "Light"
    case .dark: "Dark"
    case .system: "System"
    }
  }

  /// What to hand SwiftUI. Nothing means "follow the system", which is
  /// what `preferredColorScheme(nil)` already does.
  var colorScheme: ColorScheme? {
    switch self {
    case .light: .light
    case .dark: .dark
    case .system: nil
    }
  }
}

/// Whether Rondo opens itself when the person logs in.
///
/// The system owns this switch, not a preference of ours: it survives a
/// reinstall, the person can revoke it in System Settings, and storing our
/// own copy would let the two disagree. So this reads and writes
/// `SMAppService` directly and keeps nothing.
enum LaunchAtLogin {
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  /// Turns it on or off, reporting what went wrong rather than failing
  /// quietly - an unsigned or unregistered bundle is refused by the
  /// system, and a toggle that flips back with no explanation is worse
  /// than one that says why.
  static func set(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}
