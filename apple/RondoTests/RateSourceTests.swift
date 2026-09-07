import Foundation
import Testing

@testable import Rondo

/// Tests for reading what the rate source sends back.
///
/// None of these reach the network. What is worth holding still is the
/// decoding: the shape of the answer, and that a rate survives it exactly.
struct RateSourceTests {
  /// A real answer, copied from `api.frankfurter.dev/v2/rates` rather than
  /// invented, so a change in the source's shape shows up here.
  static let sample = #"""
    [{"date":"2026-01-05","base":"EUR","quote":"CNY","rate":7.8044},
     {"date":"2026-01-05","base":"EUR","quote":"USD","rate":1.1705}]
    """#

  @Test("The flat v2 records decode into quotes")
  func decodesTheAnswer() throws {
    let quotes = try JSONDecoder().decode(
      [RateSource.Quote].self, from: Data(Self.sample.utf8))

    #expect(quotes.count == 2)
    #expect(quotes[0].quote == "CNY")
    #expect(quotes[0].date == "2026-01-05")
    #expect(quotes[0].base == "EUR")
  }

  @Test("A rate arrives exactly, never rounded through a double")
  func ratesDecodeExactly() throws {
    let quotes = try JSONDecoder().decode(
      [RateSource.Quote].self, from: Data(Self.sample.utf8))
    #expect("\(quotes[0].rate)" == "7.8044")
    #expect("\(quotes[1].rate)" == "1.1705")

    // Those two would survive a detour through Double as well:
    // `Decimal(Double)` rounds back to the shortest form, so a rate of a
    // few decimals comes out right either way, and a test built only on
    // realistic rates would pass over a decoder that went through one.
    // This is a value long enough to tell them apart - through a Double it
    // is 1.0000000000999999488.
    let long = try JSONDecoder().decode(
      [RateSource.Quote].self,
      from: Data(#"[{"date":"2026-01-05","base":"EUR","quote":"X","rate":1.0000000001}]"#.utf8))
    #expect("\(long[0].rate)" == "1.0000000001")
  }

  @Test("A quote becomes a rate the core will accept")
  func quoteConvertsToStoredRate() throws {
    let quotes = try JSONDecoder().decode(
      [RateSource.Quote].self, from: Data(Self.sample.utf8))
    let stored = quotes[1].stored

    // The currency stored is the *quote*, not the base: the row says how
    // many USD one EUR bought, and it is filed under USD.
    #expect(stored.currency == "USD")
    #expect(stored.effectiveOn == "2026-01-05")
    #expect(stored.rate == "1.1705")
    // Never marked as hand-entered, or a refresh would start refusing to
    // overwrite its own earlier answers.
    #expect(stored.isManual == false)
  }

  @Test("A fetched rate is one the core actually stores")
  func storedRateSurvivesTheCore() throws {
    // Proof the shape is right all the way through rather than only in
    // Swift: hand it to a real core and read it back.
    let rondo = try Rondo.openInMemory()
    let quotes = try JSONDecoder().decode(
      [RateSource.Quote].self, from: Data(Self.sample.utf8))

    #expect(try rondo.recordRates(rates: quotes.map(\.stored)) == 2)
    let back = try rondo.rateInForce(currency: "USD", on: "2026-01-05")
    #expect(back?.rate == "1.1705")
  }

  @Test("An answer that is not the shape we know is a readable failure")
  func malformedAnswerIsAFailure() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        [RateSource.Quote].self, from: Data(#"{"rates":{"USD":1.17}}"#.utf8))
    }
  }

  @Test("The base asked for is the core's own, never a copy of it")
  func baseComesFromTheCore() {
    // If this side named a currency itself, changing the core's base would
    // leave Rondo fetching the old one and storing numbers whose meaning
    // no longer matches the column they sit in.
    #expect(baseCurrency() == "EUR")
    #expect(baseCurrency().count == 3)
  }
}
