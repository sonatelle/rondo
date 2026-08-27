import Foundation
import Testing

@testable import Rondo

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
    #expect(Formatting.relative("nonsense").isEmpty)
  }

  @Test("A civil date renders as a day on a calendar")
  func civilDateRenders() {
    let rendered = Formatting.date("2026-02-28")
    #expect(rendered.contains("2026"))
    #expect(rendered.contains("28"))
  }

  @Test("A restore says what it changed and stays quiet about what it did not")
  func restoreReportsOnlyWhatHappened() {
    let summary = ImportSummary(
      categoriesAdded: 0,
      categoriesUpdated: 0,
      subscriptionsAdded: 3,
      subscriptionsUpdated: 1
    )
    let sentence = Formatting.restored(summary)

    #expect(sentence.contains("3 subscriptions added"))
    // Singular, rather than "1 subscriptions updated".
    #expect(sentence.contains("1 subscription updated"))
    // The categories it did not touch are absent, not reported as zero.
    #expect(!sentence.contains("categor"))
  }

  @Test("An empty backup is explained rather than shown as an empty sentence")
  func emptyRestoreIsExplained() {
    let nothing = ImportSummary(
      categoriesAdded: 0,
      categoriesUpdated: 0,
      subscriptionsAdded: 0,
      subscriptionsUpdated: 0
    )
    #expect(!Formatting.restored(nothing).isEmpty)
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
