import Foundation
import Testing

@testable import Rondo

/// Tests for how an amount is written when there are two currencies in play.
///
/// The rules come from the design's amount card, and each of them exists
/// because the obvious alternative says something untrue.
struct AmountRulesTests {
  @Test("An amount already in the primary currency is one line without a sign")
  func sameCurrencyIsPlain() {
    let written = Formatting.amount(
      "15.90", currency: "USD", convertedTo: "USD", converted: nil)

    #expect(written.secondary == nil)
    #expect(written.isConverted == false)
    // `≈` means "converted". On an amount that was not, it is a small lie
    // printed on every row of the table.
    #expect(!written.primary.contains("≈"))
  }

  @Test("A converted amount leads with the primary currency and keeps the billed one")
  func conversionShowsBothLines() {
    let written = Formatting.amount(
      "10.00", currency: "USD", convertedTo: "CNY", converted: "71.24")

    #expect(written.isConverted)
    #expect(written.primary.hasPrefix("≈ "))
    #expect(written.primary.contains("71.24"))
    // The billed amount is still there. It is what the bank statement will
    // say, and it is the only figure in the pair that is not an estimate.
    #expect(written.secondary?.contains("10.00") == true)
  }

  @Test("An amount no rate reaches is shown billed, not converted or blanked")
  func noRateShowsTheBilledAmountOnly() {
    let written = Formatting.amount(
      "10.00", currency: "USD", convertedTo: "CNY", converted: nil)

    // One line, and it is the real one. Not a zero, not "10.00" relabelled
    // as CNY, and not the billed figure dressed up with a `≈` it has not
    // earned - every one of those reads as a number somebody can act on.
    #expect(written.secondary == nil)
    #expect(written.isConverted == false)
    #expect(!written.primary.contains("≈"))
    #expect(written.primary.contains("10.00"))
    #expect(written.primary.contains("$"))
  }

  @Test("Both lines are laid out in the reader's own numbers")
  func bothLinesFollowTheChosenLocale() {
    // The existing rule for a single amount, which must not be lost by
    // going through the two-line entry point: a column mixing "₺1.499,99"
    // and "¥1,499.99" cannot be read down.
    let written = Formatting.amount(
      "1499.99", currency: "USD", convertedTo: "CNY", converted: "10685.93")

    let plainBilled = Formatting.amount("1499.99", currency: "USD")
    let plainConverted = Formatting.amount("10685.93", currency: "CNY")
    #expect(written.secondary == plainBilled)
    #expect(written.primary == "≈ " + plainConverted)
  }

  @Test("A rate is shortened to something a person can read")
  func rateIsRoundedForReading() {
    // A cross rate is a division, so the core's exact answer runs to the
    // end of the decimal type. One EUR in rupees reached the overview as
    // "0.0710251274581209031318281136" and made four lines of small print
    // out of a one-line footnote.
    #expect(Formatting.rate("0.0710251274581209031318281136") == "0.071")
    #expect(Formatting.rate("7.1240") == "7.124")
    #expect(Formatting.rate("8") == "8")
  }

  @Test("A very small rate is never rounded away to zero")
  func tinyRateKeepsItsDigits() {
    // Four decimal places would make this "0", which reads as free. It
    // takes a currency worth ten thousand of another, but that is not a
    // reason to print the one answer that is certainly wrong.
    let written = Formatting.rate("0.00001234")
    #expect(written != "0")
    #expect(written.contains("1"))
  }

  @Test("An amount the core would not have written comes back readable")
  func unparseableAmountDoesNotVanish() {
    // Defensive rather than expected: the core writes decimals with a dot
    // and nothing else. If one ever arrived malformed, showing the raw text
    // beats showing an empty cell where money should be.
    let written = Formatting.amount(
      "not a number", currency: "USD", convertedTo: "USD", converted: nil)

    #expect(written.primary.contains("not a number"))
  }
}
