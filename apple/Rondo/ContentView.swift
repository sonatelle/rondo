import SwiftUI

/// The main window: a sidebar for what to show, a table of it, and what it
/// all costs.
struct ContentView: View {
  @Bindable var model: SubscriptionsModel

  /// Which rows are selected, so the menus and the toolbar have something
  /// to act on instead of every row carrying its own controls.
  @State private var selection: Set<Uuid> = []

  /// Sorted here rather than by the core: which column someone clicked is
  /// a question about this window, not about billing.
  @State private var sortOrder = [KeyPathComparator(\Renewal.date)]

  @State private var isAdding = false
  @State private var editing: Subscription?
  @State private var pendingDeletion: [Subscription] = []

  var body: some View {
    NavigationSplitView {
      Sidebar(model: model)
    } detail: {
      detail
    }
    .sheet(isPresented: $isAdding) {
      SubscriptionFormView(model: model)
    }
    .sheet(item: $editing) { subscription in
      SubscriptionFormView(model: model, editing: subscription)
    }
    .confirmationDialog(
      deletionTitle,
      isPresented: Binding(
        get: { !pendingDeletion.isEmpty },
        set: {
          if !$0 {
            pendingDeletion = []
          }
        }
      )
    ) {
      Button("Delete", role: .destructive) {
        for subscription in pendingDeletion {
          model.delete(subscription)
        }
        pendingDeletion = []
      }
    } message: {
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

  private var detail: some View {
    VStack(spacing: 0) {
      if model.renewals.isEmpty {
        EmptyState(model: model, add: { isAdding = true })
      } else {
        table
      }
      Divider()
      SpendingFooter(summaries: model.summaries)
    }
    .navigationTitle(model.filter.title)
    .toolbar {
      ToolbarItem {
        Button {
          isAdding = true
        } label: {
          Label("Add Subscription", systemImage: "plus")
        }
        .help("Add a subscription")
      }
    }
  }

  private var table: some View {
    Table(model.renewals, selection: $selection, sortOrder: $sortOrder) {
      TableColumn("Name", value: \.subscription.name) { renewal in
        HStack(spacing: 6) {
          Text(renewal.subscription.name)
          if renewal.subscription.status == .archived {
            Text("Archived")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.quaternary, in: Capsule())
          }
        }
      }
      TableColumn("Price", value: \.amountValue) { renewal in
        Text(
          Formatting.amount(
            renewal.subscription.amount,
            currency: renewal.subscription.currency
          )
        )
        .monospacedDigit()
      }
      .width(min: 90, ideal: 110)
      TableColumn("Cycle", value: \.cycleDays) { renewal in
        Text(renewal.cycleDescription).foregroundStyle(.secondary)
      }
      .width(min: 90, ideal: 120)
      TableColumn("Next charge", value: \.date) { renewal in
        HStack {
          Text(Formatting.date(renewal.date))
          Spacer()
          Text(Formatting.relative(renewal.date))
            .foregroundStyle(.secondary)
        }
      }
      .width(min: 160, ideal: 220)
    }
    .onChange(of: sortOrder) { _, order in
      model.sort(using: order)
    }
    .contextMenu(forSelectionType: Uuid.self) { ids in
      menuItems(for: ids)
    } primaryAction: { ids in
      editing = subscriptions(for: ids).first
    }
  }

  @ViewBuilder
  private func menuItems(for ids: Set<Uuid>) -> some View {
    let chosen = subscriptions(for: ids)
    if chosen.count == 1, let only = chosen.first {
      Button("Edit…") { editing = only }
    }
    if chosen.contains(where: { $0.status == .active }) {
      Button("Archive") {
        for subscription in chosen where subscription.status == .active {
          model.setArchived(subscription, true)
        }
      }
    }
    if chosen.contains(where: { $0.status == .archived }) {
      Button("Restore") {
        for subscription in chosen where subscription.status == .archived {
          model.setArchived(subscription, false)
        }
      }
    }
    if !chosen.isEmpty {
      Button("Delete…", role: .destructive) { pendingDeletion = chosen }
    }
  }

  private func subscriptions(for ids: Set<Uuid>) -> [Subscription] {
    model.renewals.filter { ids.contains($0.id) }.map(\.subscription)
  }

  private var deletionTitle: String {
    guard pendingDeletion.count == 1, let only = pendingDeletion.first else {
      return "Delete \(pendingDeletion.count) subscriptions?"
    }
    return "Delete \(only.name)?"
  }
}

/// The sidebar: what to show, and how much of it there is.
private struct Sidebar: View {
  @Bindable var model: SubscriptionsModel

  var body: some View {
    List(selection: $model.filter) {
      Section("Show") {
        ForEach(SubscriptionFilter.allCases) { filter in
          Label(filter.title, systemImage: filter.symbol)
            .badge(model.counts[filter] ?? 0)
            .tag(filter)
        }
      }
    }
    .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 260)
  }
}

/// Monthly totals, one per currency.
///
/// Along the bottom rather than the top: it is the sum of what is above it,
/// and a running total belongs at the end of the column it totals.
/// Currencies stay apart because the core never converts between them.
private struct SpendingFooter: View {
  let summaries: [SpendingSummary]

  var body: some View {
    HStack(spacing: 12) {
      if summaries.isEmpty {
        Text("Nothing scheduled").foregroundStyle(.secondary)
      } else {
        ForEach(summaries, id: \.currency) { summary in
          HStack(spacing: 4) {
            Text(Formatting.amount(summary.monthly, currency: summary.currency))
              .monospacedDigit()
            Text("a month").foregroundStyle(.secondary)
          }
        }
      }
      Spacer()
    }
    .font(.callout)
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(.bar)
  }
}

/// What the window says when the table would be empty.
///
/// Each case says which of the three situations this is, because "nothing
/// here" and "nothing active" call for different next steps.
private struct EmptyState: View {
  let model: SubscriptionsModel
  let add: () -> Void

  var body: some View {
    if model.filter == .active, (model.counts[.archived] ?? 0) > 0 {
      ContentUnavailableView {
        Label("Nothing active", systemImage: "archivebox")
      } description: {
        Text("Everything here is archived. Show it to restore or remove it.")
      } actions: {
        Button("Show Archived") { model.filter = .archived }
        Button("Add Subscription", action: add)
      }
    } else if model.filter == .archived {
      ContentUnavailableView(
        "Nothing archived",
        systemImage: "archivebox",
        description: Text("Archiving keeps a subscription's record but stops counting it.")
      )
    } else {
      ContentUnavailableView {
        Label("No subscriptions yet", systemImage: "repeat")
      } description: {
        Text("Add one to start tracking what renews and when.")
      } actions: {
        Button("Add Subscription", action: add)
      }
    }
  }
}
