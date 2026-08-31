import SwiftUI

/// The design's measurements, in one place.
///
/// The colours live in the asset catalogue instead, because they need a
/// light and a dark value each and the catalogue is what resolves between
/// them. Everything here is a single number that does not vary by
/// appearance.
enum Theme {
  /// The spacing scale. The design uses only these steps; a gap that is
  /// not on the scale is a mistake rather than a decision.
  enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let l: CGFloat = 10
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 14
    static let card: CGFloat = 16
    static let section: CGFloat = 20
    static let block: CGFloat = 22
    static let window: CGFloat = 24
  }

  /// Corner radii, largest surface to smallest control.
  enum Radius {
    static let largeCard: CGFloat = 16
    static let card: CGFloat = 12
    static let mediumCard: CGFloat = 14
    static let tile: CGFloat = 10
    static let iconBlock: CGFloat = 9
    static let control: CGFloat = 7
    static let sidebarItem: CGFloat = 8
    /// Anything meant to read as a pill; the exact number only has to
    /// exceed half the height.
    static let pill: CGFloat = 999
  }

  /// The type scale, named for what each size is used on rather than for
  /// its number, so a view reads as the design does.
  enum Font {
    static let windowTitle = SwiftUI.Font.system(size: 28, weight: .bold)
    static let detailName = SwiftUI.Font.system(size: 22, weight: .semibold)
    static let statFigure = SwiftUI.Font.system(size: 22, weight: .semibold)
    static let analyticsFigure = SwiftUI.Font.system(size: 24, weight: .semibold)
    static let sectionTitle = SwiftUI.Font.system(size: 14, weight: .semibold)
    static let cardTitle = SwiftUI.Font.system(size: 12, weight: .semibold)
    static let groupTitle = SwiftUI.Font.system(size: 11.5, weight: .semibold)
    static let rowTitle = SwiftUI.Font.system(size: 14, weight: .medium)
    static let sidebarItem = SwiftUI.Font.system(size: 13.5)
    static let sidebarItemSelected = SwiftUI.Font.system(size: 13.5, weight: .semibold)
    static let body = SwiftUI.Font.system(size: 13.5)
    static let label = SwiftUI.Font.system(size: 13)
    static let caption = SwiftUI.Font.system(size: 12.5)
    static let footnote = SwiftUI.Font.system(size: 11.5)
  }

  /// The card shadow. Two layers in light - a hairline and a soft lift -
  /// and one flatter layer in dark, where a spread shadow only muddies a
  /// dark surface.
  struct CardShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
      if scheme == .dark {
        content.shadow(color: .black.opacity(0.3), radius: 1, y: 1)
      } else {
        content
          .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
          .shadow(color: .black.opacity(0.18), radius: 10, y: 8)
      }
    }
  }
}

extension View {
  /// The lift the design gives every card.
  func cardShadow() -> some View {
    modifier(Theme.CardShadow())
  }
}

/// How soon a charge lands, which is the only thing in this interface that
/// carries colour.
///
/// The rest of the app stays neutral grey on purpose: when everything is
/// coloured, nothing reads as urgent. The thresholds live here rather than
/// in the core because they are a decision about emphasis, not about
/// billing - the core says when a charge falls, and this says how loudly
/// to say it.
enum Urgency {
  case urgent
  case soon
  case distant

  /// Classifies a charge date against the day the person is looking at.
  ///
  /// The reference day is passed in rather than read from the clock, for
  /// the same reason the core takes one: only the view knows which day it
  /// is showing, and a stale "in 3 days" is worse than none.
  static func of(_ date: CivilDate, from reference: CivilDate) -> Urgency {
    guard
      let charge = Formatting.parseCivilDate(date),
      let today = Formatting.parseCivilDate(reference),
      let days = Calendar.current.dateComponents([.day], from: today, to: charge).day
    else {
      return .distant
    }
    if days <= 3 {
      return .urgent
    }
    if days <= 7 {
      return .soon
    }
    return .distant
  }

  /// The pill behind the day count, or nothing when the charge is far
  /// enough off that it needs no emphasis.
  var background: Color? {
    switch self {
    case .urgent: .urgentBackground
    case .soon: .warnBackground
    case .distant: nil
    }
  }

  var foreground: Color {
    switch self {
    case .urgent: .urgentForeground
    case .soon: .warnForeground
    case .distant: .textMuted
    }
  }
}

/// The design's palette, resolved from the asset catalogue.
///
/// Views name a role - `surface`, `textMuted` - and never a value, so the
/// light and dark sets stay in one place.
extension Color {
  static let surface = Color("surface")
  static let surfaceRaised = Color("surfaceRaised")
  static let sidebar = Color("sidebar")

  static let textPrimary = Color("textPrimary")
  static let textSecondary = Color("textSecondary")
  static let textTertiary = Color("textTertiary")
  static let textMuted = Color("textMuted")
  static let textFaint = Color("textFaint")

  static let separatorLine = Color("separator")
  static let fieldBackground = Color("fieldBackground")
  static let hoverBackground = Color("hoverBackground")
  static let sidebarHover = Color("sidebarHover")

  static let brand = Color("accent")
  static let brandPressed = Color("accentPressed")
  static let linkText = Color("link")
  static let success = Color("success")
  static let danger = Color("danger")

  static let urgentBackground = Color("urgentBackground")
  static let urgentForeground = Color("urgentForeground")
  static let warnBackground = Color("warnBackground")
  static let warnForeground = Color("warnForeground")

  static let iconBlueBackground = Color("iconBlueBackground")
  static let iconBlueForeground = Color("iconBlueForeground")
  static let iconNeutralBackground = Color("iconNeutralBackground")
  static let iconNeutralForeground = Color("iconNeutralForeground")
  static let iconWarmBackground = Color("iconWarmBackground")
  static let iconWarmForeground = Color("iconWarmForeground")
  static let iconGreenBackground = Color("iconGreenBackground")
  static let iconGreenForeground = Color("iconGreenForeground")

  static let navOverview = Color("navOverview")
  static let navAll = Color("navAll")
  static let navCalendar = Color("navCalendar")
  static let navAnalytics = Color("navAnalytics")
  static let navArchived = Color("navArchived")
  static let categoryVideo = Color("categoryVideo")
  static let categoryTools = Color("categoryTools")
  static let categoryStorage = Color("categoryStorage")
}
