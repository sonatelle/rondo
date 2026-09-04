import Foundation

/// Turning the core's plain strings into words for this person's locale.
///
/// This is the frontend's half of the split: the core decides *when* a
/// subscription renews and *how much* it costs, and getting either wrong
/// is a wrong answer. Deciding that a date reads "in 10 days" and that an
/// amount reads "US$15.90" is localization, where Foundation already knows
/// far more than we would encode by hand.
enum Formatting {
  // Words, dates and numbers follow the language the person chose, not
  // the Mac's region. The two differ: an English interface on a Chinese
  // Mac was dating charges in Chinese and joining English clauses with a
  // Chinese conjunction.
  //
  // Which calendar *day* it is stays with the region, though - see
  // `civilDate(from:)`. What day it is where you are standing is not a
  // question about which language you read.

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
    formatter.locale = Localization.locale
    formatter.currencyCode = currency
    if let borrowed = Currencies.borrowedSymbols[currency] {
      formatter.currencySymbol = borrowed
    }
    return formatter.string(from: value as NSDecimalNumber) ?? "\(currency) \(text)"
  }

  /// Formats a civil date the way a calendar would show it.
  static func date(_ text: CivilDate) -> String {
    guard let date = parse(text) else { return text }
    return date.formatted(
      .dateTime.year().month(.abbreviated).day().locale(Localization.locale)
    )
  }

  /// Says how far off a date is, counted in days: "today", "tomorrow",
  /// "in 14 days".
  ///
  /// Always days, never the largest unit that fits. Foundation's relative
  /// style rounds 14 days up to "in 2 weeks", and a subscription tracker is
  /// a thing people read to know which day money leaves: a fortnight and
  /// sixteen days are the same phrase to it, and they are not the same
  /// answer. The counted phrase is asked for whole so each language carries
  /// its own plural rule.
  ///
  /// `reference` is the day to reckon from - the same day the core was
  /// asked about, so a window left open overnight cannot measure one row
  /// against yesterday and the next against today.
  static func relative(_ text: CivilDate, from reference: CivilDate) -> String {
    guard let date = parse(text), let from = parse(reference) else { return "" }
    let calendar = Calendar.current
    guard let days = calendar.dateComponents(
      [.day],
      from: calendar.startOfDay(for: from),
      to: calendar.startOfDay(for: date)
    ).day else { return "" }

    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch days {
    case 0: String(localized: "Today", bundle: bundle, locale: locale,
                   comment: "How soon a charge falls")
    case 1: String(localized: "Tomorrow", bundle: bundle, locale: locale,
                   comment: "How soon a charge falls")
    case ..<0: String(localized: "\(-days) days ago", bundle: bundle, locale: locale,
                      comment: "How long ago a charge fell")
    default: String(localized: "in \(days) days", bundle: bundle, locale: locale,
                    comment: "How soon a charge falls")
    }
  }

  /// A subscription's cycle and category on one line: "Monthly · Storage".
  ///
  /// Assembled from whole phrases joined by a separator rather than from a
  /// sentence, because a sentence would carry English word order into every
  /// language. The separator is the same in both, which is why it can be
  /// written here.
  static func cycleAndCategory(_ renewal: Renewal, categories: [Category]) -> String {
    let cycle = renewal.cycleDescription
    guard let id = renewal.subscription.categoryId,
          let category = categories.first(where: { $0.id == id })
    else { return cycle }
    return "\(cycle) · \(Categories.name(category.name, iconKey: category.iconKey))"
  }

  /// How the next charge reads under a name: "3 Sep · Monthly".
  ///
  /// The date in full rather than as "in 3 days", because the badge beside
  /// it already says how soon; saying it twice in different words would
  /// invite the reader to look for a difference.
  static func chargeSummary(_ renewal: Renewal, reference _: CivilDate) -> String {
    "\(date(renewal.date)) · \(renewal.cycleDescription)"
  }

  /// What restoring a backup changed, in a sentence.
  ///
  /// Each clause is asked for with its own count, so the catalogue can
  /// carry a plural rule per language: English needs "1 subscription" and
  /// "3 subscriptions", Chinese needs neither. Choosing the wording here,
  /// as this once did, hard-codes English grammar into the app.
  ///
  /// Counts of zero are left out rather than shown as "0 added", so the
  /// sentence says only what happened. An entry overwritten with identical
  /// values still counts as updated: the core reports what it wrote, and
  /// claiming otherwise would mean comparing values here.
  static func restored(_ summary: ImportSummary) -> String {
    var parts: [String] = []
    if summary.subscriptionsAdded > 0 {
      parts.append(String(localized: "\(summary.subscriptionsAdded) subscriptions added", bundle: Localization.bundle, locale: Localization.locale))
    }
    if summary.subscriptionsUpdated > 0 {
      parts.append(String(localized: "\(summary.subscriptionsUpdated) subscriptions updated", bundle: Localization.bundle, locale: Localization.locale))
    }
    if summary.categoriesAdded > 0 {
      parts.append(String(localized: "\(summary.categoriesAdded) categories added", bundle: Localization.bundle, locale: Localization.locale))
    }
    if summary.categoriesUpdated > 0 {
      parts.append(String(localized: "\(summary.categoriesUpdated) categories updated", bundle: Localization.bundle, locale: Localization.locale))
    }
    guard !parts.isEmpty else {
      return String(localized: "The file held nothing to restore.", bundle: Localization.bundle, locale: Localization.locale)
    }
    // Joined in the chosen language, not the region's. The full stop is
    // part of the sentence rather than appended, for the same reason: it
    // is a different character in Chinese.
    let joined = parts.formatted(.list(type: .and).locale(Localization.locale))
    return String(
      localized: "\(joined).",
      bundle: Localization.bundle,
      locale: Localization.locale,
      comment: "A restore's clauses, made into a sentence"
    )
  }

  /// Writes a picked date as the calendar day the person chose.
  ///
  /// Taken from the current calendar rather than by formatting the
  /// instant, so a date picked late in the evening does not travel to the
  /// core as tomorrow.
  ///
  /// This one keeps `Calendar.current` on purpose, where the rest of this
  /// file follows the chosen language: which day it is depends on where
  /// someone is, not on which language they read the app in.
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
