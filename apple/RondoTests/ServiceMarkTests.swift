import Foundation
import Testing

@testable import Rondo

/// Tests for the letters a service block carries.
struct ServiceMarkTests {
  @Test("A plain name gives one capital")
  func singleInitial() {
    #expect(ServiceMark.initials(of: "Notion Plus") == "N")
    #expect(ServiceMark.initials(of: "spotify") == "S")
  }

  @Test("A camel-cased name keeps both letters")
  func camelCaseKeepsTwo() {
    // "I" would not tell iCloud from iA Writer, and both are plausible
    // things to be paying for.
    #expect(ServiceMark.initials(of: "iCloud+ 200GB") == "iC")
    #expect(ServiceMark.initials(of: "iA Writer") == "iA")
  }

  @Test("A name in a script without letter case is left alone")
  func uncasedScriptIsUnchanged() {
    // Uppercasing these is a no-op, but the block must still show the
    // character rather than an empty square.
    #expect(ServiceMark.initials(of: "网易云音乐黑胶") == "网")
    #expect(ServiceMark.initials(of: "爱奇艺") == "爱")
  }

  @Test("Leading spaces do not become the initial")
  func whitespaceIsTrimmed() {
    #expect(ServiceMark.initials(of: "  Netflix") == "N")
  }

  @Test("A name with nothing in it gives nothing")
  func emptyNameIsEmpty() {
    // The core refuses a blank name, so this should not arise - but an
    // index into an empty string would crash rather than render oddly.
    #expect(ServiceMark.initials(of: "") == "")
    #expect(ServiceMark.initials(of: "   ") == "")
  }
}
