import Foundation

/// Whether the calendar is showing one month or a whole year.
///
/// The two answer different questions, which is why both exist. A month
/// says which day money leaves; a year says only which months turn out to
/// be expensive, because a yearly plan lands its whole price in one of
/// them and nothing in the other eleven.
enum CalendarScale: String, CaseIterable, Identifiable {
  case month
  case year

  var id: String {
    rawValue
  }

  /// The calendar unit a span of this scale covers, which is also the unit
  /// the arrows page by.
  var component: Calendar.Component {
    switch self {
    case .month: .month
    case .year: .year
    }
  }

  /// A key, for the same reason as `Navigation.title`.
  var title: String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch self {
    case .month: String(localized: "Month", bundle: bundle, locale: locale,
                        comment: "Calendar scale: one month at a time")
    case .year: String(localized: "Year", bundle: bundle, locale: locale,
                       comment: "Calendar scale: twelve months at once")
    }
  }

  /// What the button beside the arrows says: it comes back to the month
  /// somebody is living in, or to the year, depending on what is on screen.
  var todayTitle: String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch self {
    case .month: String(localized: "Today", bundle: bundle, locale: locale,
                        comment: "Brings the calendar back to this month")
    case .year: String(localized: "This Year", bundle: bundle, locale: locale,
                       comment: "Brings the calendar back to the current year")
    }
  }
}
