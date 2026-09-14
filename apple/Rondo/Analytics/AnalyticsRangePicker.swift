import SwiftUI

/// Which twelve months the chart covers.
///
/// A menu rather than a segmented control: the labels are sentences
/// ("Last 12 months") rather than single words, and segments holding
/// sentences stretch the toolbar out of shape. The month/year switch on
/// the calendar is segmented for the opposite reason.
struct AnalyticsRangePicker: View {
  let model: SubscriptionsModel

  @State private var isHovering = false

  var body: some View {
    Menu {
      ForEach(AnalyticsRange.allCases) { range in
        Button {
          model.setAnalyticsRange(range)
        } label: {
          // A tick beside the one in force, which is what a menu uses to
          // say "this is the current choice".
          if model.analyticsRange == range {
            Label(range.title, systemImage: "checkmark")
          } else {
            Text(verbatim: range.title)
          }
        }
      }
    } label: {
      HStack(spacing: Theme.Space.s) {
        Text(verbatim: model.analyticsRange.title)
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textSecondary)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Color.textFaint)
      }
      .padding(.horizontal, Theme.Space.l)
      .frame(height: 26)
      .background(
        isHovering ? Color.hoverBackground : Color.fieldBackground,
        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { isHovering = $0 }
  }
}
