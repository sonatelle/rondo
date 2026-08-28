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

  /// Reads an amount the core wrote, without letting the locale reinterpret
  /// the separator.
  static func decimal(_ text: DecimalString) -> Decimal? {
    Decimal(string: text, locale: machine)
  }

  /// Formats an exact amount as currency, or returns it plainly if the
  /// code is one the system does not know.
  ///
  /// The number is laid out this person's way - their separators, their
  /// digits - whatever currency it is in. Formatting each amount in the
  /// currency's own home locale would fetch a nicer symbol but bring that
  /// locale's numbers with it, and a column holding "₺1.499,99" beside
  /// "¥1,499.99" cannot be read down.
  static func amount(_ text: DecimalString, currency: String) -> String {
    guard let value = decimal(text) else {
      return "\(currency) \(text)"
    }
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    if let borrowed = borrowedSymbols[currency] {
      formatter.currencySymbol = borrowed
    }
    return formatter.string(from: value as NSDecimalNumber) ?? "\(currency) \(text)"
  }

  /// Symbols taken from the places that spend a currency, for the codes
  /// this person's own locale has no symbol for.
  ///
  /// Their locale is left in charge wherever it has an answer, because its
  /// answers are deliberately told apart: a Chinese reader is shown "JP¥"
  /// and "¥" for yen and yuan, and replacing the first with the "¥" Japan
  /// writes would make two currencies identical in one list. It names only
  /// about twenty codes, though, and the rest arrived as bare "TRY" and
  /// "PLN"; borrowing covers all but fourteen of the remainder.
  ///
  /// Built once, on first use, at a cost of about seventeen milliseconds -
  /// finding these means walking every locale the system knows.
  private static let borrowedSymbols: [String: String] = {
    var spenders: [String: [Locale]] = [:]
    for identifier in Locale.availableIdentifiers {
      let locale = Locale(identifier: identifier)
      guard let code = locale.currency?.identifier else { continue }
      spenders[code, default: []].append(locale)
    }

    var borrowed: [String: String] = [:]
    for code in Locale.commonISOCurrencyCodes where symbol(for: code, in: .current) == nil {
      for locale in spenders[code] ?? [] {
        if let theirs = symbol(for: code, in: locale) {
          borrowed[code] = theirs
          break
        }
      }
    }
    return borrowed
  }()

  /// One locale's symbol for a code, or nothing when it just echoes it.
  private static func symbol(for code: String, in locale: Locale) -> String? {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = locale
    formatter.currencyCode = code
    guard let symbol = formatter.currencySymbol, symbol != code else { return nil }
    return symbol
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

  /// What restoring a backup changed, in a sentence.
  ///
  /// Counts of zero are left out rather than shown as "0 added", so the
  /// sentence says only what happened. An entry overwritten with identical
  /// values still counts as updated: the core reports what it wrote, and
  /// claiming otherwise would mean comparing values here.
  static func restored(_ summary: ImportSummary) -> String {
    let parts = [
      counted(summary.subscriptionsAdded, "subscription", "subscriptions", "added"),
      counted(summary.subscriptionsUpdated, "subscription", "subscriptions", "updated"),
      counted(summary.categoriesAdded, "category", "categories", "added"),
      counted(summary.categoriesUpdated, "category", "categories", "updated"),
    ].compactMap { $0 }
    guard !parts.isEmpty else {
      return "The file held nothing to restore."
    }
    return parts.formatted(.list(type: .and)) + "."
  }

  /// One clause of that sentence, or nothing when it would say zero.
  private static func counted(
    _ count: UInt32,
    _ singular: String,
    _ plural: String,
    _ verb: String
  ) -> String? {
    guard count > 0 else { return nil }
    return "\(count) \(count == 1 ? singular : plural) \(verb)"
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
