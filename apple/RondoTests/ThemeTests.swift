import AppKit
import Testing

@testable import Rondo

/// Tests for the design tokens.
///
/// `Color("name")` does not fail when the catalogue has no such colour: it
/// renders a fallback and says nothing, so a typo survives the compiler and
/// every build. These check the catalogue actually answers.
struct ThemeTests {
  /// Resolves a named colour the way the catalogue does, under one
  /// appearance, or fails the test if there is no such name.
  private func resolved(_ name: String, dark: Bool) throws -> NSColor {
    let colour = try #require(
      NSColor(named: name),
      "no colour named \(name) in the asset catalogue"
    )
    let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
    var srgb: NSColor?
    appearance.performAsCurrentDrawingAppearance {
      srgb = colour.usingColorSpace(.sRGB)
    }
    return try #require(srgb)
  }

  private func hex(_ colour: NSColor) -> String {
    String(
      format: "#%02x%02x%02x",
      Int((colour.redComponent * 255).rounded()),
      Int((colour.greenComponent * 255).rounded()),
      Int((colour.blueComponent * 255).rounded())
    )
  }

  @Test("The catalogue carries both appearances, with the design's values")
  func coloursCarryBothAppearances() throws {
    // Taken from the handoff's token tables. If the dark half were missing
    // the catalogue would answer with the light value under both, which is
    // exactly what this compares.
    #expect(hex(try resolved("surface", dark: false)) == "#f7f6f5")
    #expect(hex(try resolved("surface", dark: true)) == "#1b1a19")
    #expect(hex(try resolved("urgentForeground", dark: false)) == "#c03f22")
    #expect(hex(try resolved("urgentForeground", dark: true)) == "#ff9481")
    #expect(hex(try resolved("textPrimary", dark: false)) == "#1c1b1a")
    #expect(hex(try resolved("textPrimary", dark: true)) == "#f2f0ee")
  }

  @Test("A name the catalogue does not have resolves to nothing")
  func missingNameIsDetectable() {
    // Proves the check above can fail. Without this, a catalogue that
    // answered for everything would make the test vacuous.
    #expect(NSColor(named: "notAColourInThisCatalogue") == nil)
  }

  @Test("Urgency turns a charge date into the emphasis it deserves")
  func urgencyThresholds() {
    let today = "2026-03-01"
    #expect(Urgency.of("2026-03-01", from: today) == .urgent)
    #expect(Urgency.of("2026-03-04", from: today) == .urgent)
    // Three days is the last urgent day; four is only soon.
    #expect(Urgency.of("2026-03-05", from: today) == .soon)
    #expect(Urgency.of("2026-03-08", from: today) == .soon)
    #expect(Urgency.of("2026-03-09", from: today) == .distant)
  }

  @Test("A charge already past reads as urgent rather than calm")
  func overdueIsUrgent() {
    // The core only ever answers with charges on or after the day asked
    // about, so this should not arise - but a date that slipped into the
    // past must not come back as "distant", which would render it in the
    // same grey as something months away.
    #expect(Urgency.of("2026-02-27", from: "2026-03-01") == .urgent)
  }

  @Test("An unparseable date falls back to no emphasis")
  func malformedDateIsCalm() {
    // Colouring on a value we could not read would be inventing urgency.
    #expect(Urgency.of("nonsense", from: "2026-03-01") == .distant)
  }
}
