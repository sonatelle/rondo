import SwiftUI

/// One amount, with the currency it is billed in beneath it when the two
/// differ.
///
/// The design writes every single amount this way - the converted figure at
/// the size the surrounding text is set in, the billed one smaller and
/// muted - and it appears in the table, the overview cards, the upcoming
/// list and the detail page. Written once so those four cannot drift apart,
/// and so the rule about when there is a second line at all lives in one
/// place: `Formatting.amount(_:currency:convertedTo:converted:)` decides
/// that, and this only draws what it decided.
struct TwoLineAmount: View {
  let written: Formatting.Amount
  /// The size the first line is set in; the second is always a footnote.
  let font: Font
  /// Whether the first line is muted. The second always is.
  var faded = false

  var body: some View {
    VStack(alignment: .trailing, spacing: 1) {
      Text(verbatim: written.primary)
        .font(font)
        .monospacedDigit()
        .foregroundStyle(faded ? Color.textMuted : Color.textPrimary)
        // An amount never wraps. Broken across lines it stops being a
        // number: "₹700.00" came back as "₹70 / 0.0 / 0".
        .lineLimit(1)
      if let secondary = written.secondary {
        Text(verbatim: secondary)
          .font(Theme.Font.footnote)
          .monospacedDigit()
          .foregroundStyle(Color.textFaint)
          .lineLimit(1)
      }
    }
  }
}
