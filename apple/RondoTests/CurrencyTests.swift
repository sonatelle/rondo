import Foundation
import Testing

@testable import Rondo

/// Tests for the list of currencies the form offers.
struct CurrencyTests {
  @Test("The list covers the currencies the system knows")
  func listIsPopulated() {
    #expect(Currencies.all.count > 100)
    #expect(Currencies.all.contains("USD"))
    #expect(Currencies.all.contains("CNY"))
    // Every entry is a shape the core will accept.
    #expect(Currencies.all.allSatisfy { $0.count == 3 && $0.allSatisfy(\.isUppercase) })
  }

  @Test("A currency the list does not know is added rather than dropped")
  func unknownSelectionSurvives() {
    // A backup written elsewhere can carry a code this system no longer
    // lists. A picker with no row for its own value shows blank and
    // rewrites the field on the next edit.
    let list = Currencies.including("XBT")
    #expect(list.first == "XBT")
    #expect(list.count == Currencies.all.count + 1)
  }

  @Test("A currency the list already knows is not added twice")
  func knownSelectionIsNotDuplicated() {
    let list = Currencies.including("USD")
    #expect(list.count == Currencies.all.count)
    #expect(list.filter { $0 == "USD" }.count == 1)
  }

  @Test("A new subscription starts in this Mac's own currency")
  func preferredIsThreeLetters() {
    // Hardcoding one currency is wrong for everyone who does not use it.
    #expect(Currencies.preferred.count == 3)
  }
}
