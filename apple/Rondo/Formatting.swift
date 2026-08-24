import Foundation

/// Turning the core's plain strings into words for this person's locale.
///
/// This is the frontend's half of the split: the core decides *when* a
/// subscription renews and *how much* it costs, and getting either wrong
/// is a wrong answer. Deciding that a date reads "in 10 days" and that an
/// amount reads "US$15.90" is localization, where Foundation already knows
/// far more than we would encode by hand.
enum Formatting {
  /// The core always writes decimals with a dot, whatever the locale.
  ///
  /// `Decimal(string:)` would otherwise read "15.90" against a comma
  /// locale and quietly return 1590.
  private static let machine = Locale(identifier: "en_US_POSIX")

  /// Formats an exact amount as currency, or returns it plainly if the
  /// code is one the system does not know.
  static func amount(_ text: DecimalString, currency: String) -> String {
    guard let value = Decimal(string: text, locale: machine) else {
      return "\(currency) \(text)"
    }
    return value.formatted(.currency(code: currency))
  }

  /// Formats a civil date the way a calendar would show it.
  static func date(_ text: CivilDate) -> String {
    guard let date = parse(text) else { return text }
    return date.formatted(.dateTime.year().month(.abbreviated).day())
  }

  /// Says how far off a date is from now: "today", "tomorrow", "in 10 days".
  static func relative(_ text: CivilDate) -> String {
    guard let date = parse(text) else { return "" }
    return date.formatted(.relative(presentation: .named))
  }

  /// Writes a picked date as the calendar day the person chose.
  ///
  /// Taken from the current calendar rather than by formatting the
  /// instant, so a date picked late in the evening does not travel to the
  /// core as tomorrow.
  static func civilDate(from date: Date) -> CivilDate {
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      parts.year ?? 0,
      parts.month ?? 0,
      parts.day ?? 0
    )
  }

  /// Reads `YYYY-MM-DD` as noon in the current time zone.
  ///
  /// Noon rather than midnight so that a daylight-saving shift cannot move
  /// the date onto the day before, which would misreport every renewal in
  /// the affected week.
  static func parseCivilDate(_ text: CivilDate) -> Date? {
    parse(text)
  }

  private static func parse(_ text: CivilDate) -> Date? {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    var components = DateComponents()
    components.year = parts[0]
    components.month = parts[1]
    components.day = parts[2]
    components.hour = 12
    return Calendar.current.date(from: components)
  }
}
