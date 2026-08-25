import SwiftUI

/// What hangs off the status item: the next few charges, and the total.
///
/// This is the view for a glance, not for managing. It answers "what is
/// coming and when" without a window, and hands anything else over to the
/// main one.
struct MenuBarView: View {
  let model: SubscriptionsModel
  @Environment(\.openWindow) private var openWindow

  /// How many renewals fit before the list stops being a glance.
  private static let visible = 5

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if upcoming.isEmpty {
        Text("Nothing scheduled")
          .foregroundStyle(.secondary)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
      } else {
        ForEach(upcoming) { renewal in
          UpcomingRow(renewal: renewal)
        }
        if remaining > 0 {
          Text("and \(remaining) more")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        Divider()
        Totals(summaries: model.summaries)
      }

      Divider()
      Group {
        Button("Open Rondo") {
          openWindow(id: RondoApp.mainWindowID)
          NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Rondo") { NSApp.terminate(nil) }
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 12)
      .padding(.vertical, 3)
    }
    .padding(.vertical, 6)
    .frame(width: 260)
  }

  /// The soonest few charges. The list is short on purpose: past a handful
  /// it stops being something you take in at a glance.
  private var upcoming: [Renewal] {
    Array(model.upcoming.prefix(Self.visible))
  }

  private var remaining: Int {
    model.upcoming.count - upcoming.count
  }
}

/// One charge: what, how much, and how soon.
private struct UpcomingRow: View {
  let renewal: Renewal

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(renewal.subscription.name)
        .lineLimit(1)
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 1) {
        Text(
          Formatting.amount(
            renewal.subscription.amount,
            currency: renewal.subscription.currency
          )
        )
        .monospacedDigit()
        Text(Formatting.relative(renewal.date))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
  }
}

private struct Totals: View {
  let summaries: [SpendingSummary]

  var body: some View {
    HStack {
      Text("A month").foregroundStyle(.secondary)
      Spacer()
      VStack(alignment: .trailing, spacing: 1) {
        ForEach(summaries, id: \.currency) { summary in
          Text(Formatting.amount(summary.monthly, currency: summary.currency))
            .monospacedDigit()
        }
      }
    }
    .font(.callout)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }
}
