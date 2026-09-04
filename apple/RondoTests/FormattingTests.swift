import Foundation
@testable import Rondo
import Testing

/// Tests for the frontend's half of the split: turning the core's plain
/// strings into words, and a picked date back into one.
///
/// These are the parts of the app that can be wrong without anything
/// crashing - a date that shifts by a day, an amount that reads as a
/// thousand times its value - so they are the parts worth pinning down.
struct FormattingTests {
  @Test("A date picked late in the evening stays on its own day")
  func eveningDateDoesNotRollOver() throws {
    // Taken from the instant rather than the calendar, 23:45 local would
    // format as tomorrow anywhere east of UTC.
    let evening = try date(year: 2026, month: 1, day: 31, hour: 23, minute: 45)
    #expect(Formatting.civilDate(from: evening) == "2026-01-31")
  }

  @Test("Single-digit months and days are padded")
  func componentsArePadded() throws {
    // The core parses `YYYY-MM-DD` exactly; "2026-2-5" is not that.
    let early = try date(year: 2026, month: 2, day: 5, hour: 9, minute: 0)
    #expect(Formatting.civilDate(from: early) == "2026-02-05")
  }

  @Test("An amount keeps its value whatever the decimal separator")
  func amountSurvivesTheLocale() {
    // The core always writes a dot. Read against a comma locale without
    // saying so, `Decimal(string:)` returns 1590 for "15.90".
    #expect(Formatting.amount("15.90", currency: "USD").contains("15.90"))
    #expect(Formatting.amount("0.99", currency: "USD").contains("0.99"))
  }

  @Test("A currency the reader's locale has no symbol for borrows one")
  func symbolIsBorrowedWhenTheLocaleHasNone() {
    // These arrive as bare "TRY 499.00" and "THB 499.00" beside rows that
    // do have a symbol, which is what makes a price column look unfinished.
    #expect(Formatting.amount("499.00", currency: "TRY").contains("₺"))
    #expect(Formatting.amount("499.00", currency: "THB").contains("฿"))
  }

  @Test("Borrowing a symbol never makes two currencies look the same")
  func borrowingKeepsCurrenciesApart() {
    // Japan writes yen as "¥" and China writes yuan as "¥". A locale that
    // holds both tells them apart on purpose, and overriding its answer
    // would print one string for two currencies.
    let yen = Formatting.amount("1499.00", currency: "JPY")
    let yuan = Formatting.amount("1499.00", currency: "CNY")
    #expect(yen != yuan)
  }

  @Test("Amounts are laid out the reader's way whatever the currency")
  func numbersDoNotFollowTheCurrencyHome() {
    // Formatting in the currency's home locale would bring its separators
    // too: Turkish writes 1499.99 as "1.499,99". A column mixing that with
    // "1,499.99" cannot be read down.
    let turkish = Formatting.amount("1499.99", currency: "TRY")
    let local = Formatting.amount("1499.99", currency: "USD")
    let separators = { (text: String) in text.filter { $0 == "." || $0 == "," } }
    #expect(separators(turkish) == separators(local))
  }

  @Test("An unknown currency code still shows the amount")
  func unknownCurrencyDegradesGracefully() {
    let formatted = Formatting.amount("15.90", currency: "ZZZ")
    #expect(formatted.contains("15.90"))
    #expect(formatted.contains("ZZZ"))
  }

  @Test("An unparseable date is passed through rather than blanked")
  func malformedDateIsVisible() {
    // Showing the raw value makes a broken row obvious; an empty cell
    // would look like missing data instead of a bug.
    #expect(Formatting.date("nonsense") == "nonsense")
    #expect(Formatting.relative("nonsense", from: "2026-09-04").isEmpty)
    #expect(Formatting.relative("2026-09-04", from: "nonsense").isEmpty)
  }

  /// Always days, never the largest unit that fits. Foundation's own
  /// relative style calls fourteen days "in 2 weeks", which is the same
  /// phrase it gives sixteen - and which day money leaves is the question
  /// this app exists to answer.
  @Test("How soon a charge falls is counted in days, however many")
  func relativeDaysNeverRoundToWeeks() {
    // Which language these come back in depends on the machine, so what is
    // checked is that the day itself is named rather than counted: neither
    // may read as "in 0 days".
    let today: CivilDate = "2026-09-04"
    #expect(["Today", "今天"].contains(Formatting.relative("2026-09-04", from: today)))
    #expect(["Tomorrow", "明天"].contains(Formatting.relative("2026-09-05", from: today)))

    let fortnight = Formatting.relative("2026-09-18", from: today)
    #expect(fortnight.contains("14"), "got \(fortnight)")
    #expect(!fortnight.lowercased().contains("week"), "got \(fortnight)")

    let past = Formatting.relative("2026-09-01", from: today)
    #expect(past.contains("3"), "got \(past)")
  }

  @Test("A civil date renders as a day on a calendar")
  func civilDateRenders() {
    let rendered = Formatting.date("2026-02-28")
    #expect(rendered.contains("2026"))
    #expect(rendered.contains("28"))
  }

  @Test("A restore says what it changed, in the chosen language")
  func restoreReportsOnlyWhatHappened() {
    // Pinned rather than left to the machine: the wording now comes from
    // the catalogue, so a test that did not choose a language would be
    // asserting whatever this Mac happens to be set to.
    let summary = ImportSummary(
      categoriesAdded: 0,
      categoriesUpdated: 0,
      subscriptionsAdded: 3,
      subscriptionsUpdated: 1
    )

    let english = inLanguage("en") { Formatting.restored(summary) }
    #expect(english.contains("3 subscriptions added"))
    // Singular, and not "1 subscriptions updated". English needs the
    // distinction; the rule lives in the catalogue rather than in Swift.
    #expect(english.contains("1 subscription updated"))
    // The categories it did not touch are absent, not reported as zero.
    #expect(!english.contains("categor"))

    let chinese = inLanguage("zh-Hans") { Formatting.restored(summary) }
    #expect(chinese.contains("3 项订阅"))
    #expect(chinese.contains("1 项订阅"))
    #expect(!chinese.contains("分类"))
  }

  @Test("The sentence is joined and ended the way its own language does it")
  func sentenceFollowsItsLanguage() {
    let summary = ImportSummary(
      categoriesAdded: 0,
      categoriesUpdated: 0,
      subscriptionsAdded: 3,
      subscriptionsUpdated: 1
    )

    // The failure this pins down: clauses in one language joined by
    // another's conjunction, because the words follow the language and
    // list formatting follows the region.
    let english = inLanguage("en") { Formatting.restored(summary) }
    #expect(english.contains(" and "))
    #expect(english.hasSuffix("."))
    #expect(!english.contains("和"))

    let chinese = inLanguage("zh-Hans") { Formatting.restored(summary) }
    #expect(chinese.hasSuffix("。"))
    #expect(!chinese.contains(" and "))
  }

  @Test("An empty backup is explained rather than shown as an empty sentence")
  func emptyRestoreIsExplained() {
    let nothing = ImportSummary(
      categoriesAdded: 0,
      categoriesUpdated: 0,
      subscriptionsAdded: 0,
      subscriptionsUpdated: 0
    )
    #expect(!inLanguage("en") { Formatting.restored(nothing) }.isEmpty)
    #expect(inLanguage("zh-Hans") { Formatting.restored(nothing) }.contains("没有"))
  }

  /// Runs something with the interface pinned to one language.
  ///
  /// Restores whatever was there before, so a test cannot leave the
  /// preference changed for the next one.
  private func inLanguage<T>(_ code: String, _ body: () -> T) -> T {
    let defaults = UserDefaults.standard
    let previous = defaults.string(forKey: Preference.appLanguage)
    defaults.set(code, forKey: Preference.appLanguage)
    defer { defaults.set(previous, forKey: Preference.appLanguage) }
    return body()
  }

  /// Builds a local date, failing the test rather than crashing if the
  /// components do not name a real one.
  private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) throws -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return try #require(Calendar.current.date(from: components))
  }
}
