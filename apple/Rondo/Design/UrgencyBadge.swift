import SwiftUI

/// How soon a charge falls, coloured by how soon that is.
///
/// Urgency is the only thing in Rondo that earns a colour; everything else
/// is neutral, so that red means one thing and always the same thing. The
/// overview and the table both draw it, which is why it lives here rather
/// than inside either of them: two copies would drift, and the day they
/// disagreed about what counts as urgent nobody would notice.
struct UrgencyBadge: View {
  let date: CivilDate
  let reference: CivilDate

  var body: some View {
    let urgency = Urgency.of(date, from: reference)
    Text(verbatim: Formatting.relative(date, from: reference))
      .font(Theme.Font.caption)
      .fontWeight(urgency == .distant ? .regular : .semibold)
      .foregroundStyle(foreground(urgency))
      // The same padding whatever the urgency, so only the fill changes.
      // Giving the pill its padding and the plain text none pushed the
      // words in a badged row nine points left of the words above it, and
      // a column of dates that does not line up reads as a mistake even
      // when every date in it is right.
      .padding(.horizontal, 9)
      .padding(.vertical, 2)
      .background(background(urgency), in: Capsule())
  }

  /// A distant charge gets no pill at all - a page where everything is
  /// badged has nothing left to draw the eye with.
  private func background(_ urgency: Urgency) -> Color {
    switch urgency {
    case .urgent: .urgentBackground
    case .soon: .warnBackground
    case .distant: .clear
    }
  }

  private func foreground(_ urgency: Urgency) -> Color {
    switch urgency {
    case .urgent: .urgentForeground
    case .soon: .warnForeground
    case .distant: .textMuted
    }
  }
}
