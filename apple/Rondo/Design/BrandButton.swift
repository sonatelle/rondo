import SwiftUI

/// The one filled button in the app.
///
/// Drawn here rather than left to `.borderedProminent`, which takes the
/// system's accent colour - whatever the person set in System Settings -
/// and the system's control metrics. Beside the pills and chips, which are
/// all drawn from the design's own numbers, it was the one control that did
/// not match.
///
/// One definition rather than one per place it appears: the toolbar's "Add
/// Subscription" and the first-run screen's "Add your first subscription"
/// are the same button doing the same thing, and drawn twice they would be
/// two things to keep in step.
struct BrandButton: View {
  let title: String

  /// The design gives the toolbar's copy 26pt and the first-run screen's
  /// 32pt, with the padding either side scaled to match - a button that
  /// grows taller without growing wider reads as stubby.
  var height: CGFloat = 26
  var sidePadding: CGFloat = Theme.Space.xl

  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(verbatim: title)
        .font(Theme.Font.body)
        .fontWeight(.medium)
        .foregroundStyle(Color.white)
        .padding(.horizontal, sidePadding)
        .frame(height: height)
        .background(Color.brand, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        // The whole rectangle takes the click, not only the glyphs: a
        // filled button that ignores a press on its padding reads as
        // broken rather than as precise.
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
