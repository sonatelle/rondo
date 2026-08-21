import SwiftUI

/// The main window: what is due, and what it all costs.
struct ContentView: View {
  let model: SubscriptionsModel

  var body: some View {
    VStack(spacing: 0) {
      SpendingHeader(summaries: model.summaries)
      Divider()
      if model.renewals.isEmpty {
        ContentUnavailableView(
          "No subscriptions yet",
          systemImage: "repeat",
          description: Text("Add one to start tracking what renews and when.")
        )
      } else {
        List(model.renewals, id: \.subscription.id) { renewal in
          RenewalRow(renewal: renewal)
        }
        .listStyle(.inset)
      }
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(
        get: { model.failure != nil },
        set: {
          if !$0 {
            model.failure = nil
          }
        }
      )
    ) {
      Button("OK") { model.failure = nil }
    } message: {
      Text(model.failure ?? "")
    }
  }
}

/// Monthly and yearly totals, one line per currency.
///
/// Currencies stay apart because the core never converts between them, and
/// a single blended number would be a figure nobody actually pays.
private struct SpendingHeader: View {
  let summaries: [SpendingSummary]

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 24) {
      if summaries.isEmpty {
        Text("Nothing scheduled").foregroundStyle(.secondary)
      } else {
        ForEach(summaries, id: \.currency) { summary in
          VStack(alignment: .leading, spacing: 2) {
            Text(Formatting.amount(summary.monthly, currency: summary.currency))
              .font(.title2)
              .monospacedDigit()
            Text("per month").font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      Spacer()
    }
    .padding(.horizontal)
    .padding(.vertical, 12)
  }
}

/// One subscription and when it is next charged.
private struct RenewalRow: View {
  let renewal: Renewal

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(renewal.subscription.name)
        Text(Formatting.date(renewal.date))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
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
    .padding(.vertical, 4)
  }
}
