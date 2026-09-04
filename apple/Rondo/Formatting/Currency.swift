import Foundation

/// The currency codes a price can be recorded in.
///
/// The list is the system's, not ours: `Locale.commonISOCurrencyCodes`.
/// Keeping our own copy would mean maintaining a currency table by hand
/// and shipping it stale.
///
/// The core only checks that a code is three uppercase letters and never
/// looks at the list itself, so which codes exist is a question for this
/// side - the same split as the rest of `Formatting`. Rondo never converts
/// between currencies, so a code is a label on an amount and nothing more.
enum Currencies {
  /// Every code the system considers current, in alphabetical order.
  static let all: [String] = Locale.commonISOCurrencyCodes

  /// The list to show while `code` is selected.
  ///
  /// A subscription can hold a code this list does not - restored from a
  /// backup written elsewhere, or a currency the system has since dropped -
  /// and a picker with no row for its own value shows an empty box and
  /// silently rewrites the field on the next edit. So the value is added
  /// rather than the field being blanked.
  static func including(_ code: String) -> [String] {
    guard !code.isEmpty, !all.contains(code) else { return all }
    return [code] + all
  }

  /// What a new subscription starts in.
  ///
  /// The person's own choice wins; failing that, whatever this Mac is set
  /// to. Naming one in code would be right for whoever picked it and wrong
  /// for everyone else.
  ///
  /// This does **not** make one currency the one everything is measured
  /// in. Rondo never converts between currencies: a primary currency only
  /// decides where a form starts and which total is listed first.
  static var preferred: String {
    let chosen = UserDefaults.standard.string(forKey: Preference.primaryCurrency) ?? ""
    if !chosen.isEmpty {
      return chosen
    }
    return Locale.current.currency?.identifier ?? "USD"
  }
}
