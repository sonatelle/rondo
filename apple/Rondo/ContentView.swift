import SwiftUI

/// The main window: what is due, and what it all costs.
struct ContentView: View {
  let model: SubscriptionsModel
  @State private var isAdding = false

  /// The subscription a confirmation is being asked about.
  ///
  /// Deleting cannot be undone and there is no backup taken automatically,
  /// so it asks first and names what it would remove.
  @State private var pendingDeletion: Subscription?

  var body: some View {
    VStack(spacing: 0) {
      SpendingHeader(summaries: model.summaries)
      Divider()
      if model.renewals.isEmpty {
        ContentUnavailableView {
          Label("No subscriptions yet", systemImage: "repeat")
        } description: {
          Text("Add one to start tracking what renews and when.")
        } actions: {
          Button("Add Subscription") { isAdding = true }
        }
      } else {
        List(model.renewals, id: \.subscription.id) { renewal in
          RenewalRow(renewal: renewal)
            .contextMenu {
              Button("Archive") { model.archive(renewal.subscription) }
              Button("Delete…", role: .destructive) {
                pendingDeletion = renewal.subscription
              }
            }
        }
        .listStyle(.inset)
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isAdding = true
        } label: {
          Label("Add Subscription", systemImage: "plus")
        }
        .keyboardShortcut("n")
      }
    }
    .sheet(isPresented: $isAdding) {
      AddSubscriptionView(model: model)
    }
    .confirmationDialog(
      "Delete \(pendingDeletion?.name ?? "")?",
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: {
          if !$0 {
            pendingDeletion = nil
          }
        }
      ),
      presenting: pendingDeletion
    ) { subscription in
      Button("Delete", role: .destructive) {
        model.delete(subscription)
        pendingDeletion = nil
      }
    } message: { _ in
      Text("This cannot be undone. To stop counting it but keep the record, archive it instead.")
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
