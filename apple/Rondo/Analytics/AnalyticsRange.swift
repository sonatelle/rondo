import Foundation

/// Which twelve months the spending chart is drawn over.
///
/// Both choices are twelve months, which is deliberate: a chart whose
/// number of columns changed with the menu would be a different chart each
/// time, and comparing one reading with the next is most of what it is for.
enum AnalyticsRange: String, CaseIterable, Identifiable {
  /// The twelve months ending with this one - every bar already charged,
  /// or part way through.
  case rolling
  /// January to December of the year we are in, so the months still to
  /// come are shown as what they will cost.
  case calendarYear

  /// How many months either choice covers.
  static let months = 12

  var id: String {
    rawValue
  }

  /// A key, for the same reason as `Navigation.title`.
  var title: String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch self {
    case .rolling:
      String(localized: "Last 12 months", bundle: bundle, locale: locale,
             comment: "Analytics range: the twelve months ending with this one")
    case .calendarYear:
      String(localized: "This calendar year", bundle: bundle, locale: locale,
             comment: "Analytics range: January to December of the current year")
    }
  }

  /// The first month of the span, reckoned against the day being shown.
  ///
  /// Anchored on the first of a month in both cases, for the reason the
  /// calendar is: adding months to a day near the end of one drifts, and
  /// a chart whose columns slid by a day would be quietly wrong.
  func start(from reference: CivilDate) -> Date {
    let calendar = Calendar.current
    guard let today = Formatting.parseCivilDate(reference),
          let thisMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: today)
          )
    else { return Date() }
    return switch self {
    case .rolling:
      calendar.date(byAdding: .month, value: -(Self.months - 1), to: thisMonth) ?? thisMonth
    case .calendarYear:
      calendar.date(from: calendar.dateComponents([.year], from: today)) ?? thisMonth
    }
  }
}
