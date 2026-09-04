import SwiftUI
import UniformTypeIdentifiers

/// The main window: a sidebar for what to show, a table of it, and what it
/// all costs.
struct ContentView: View {
  @Bindable var model: SubscriptionsModel

  /// Which rows are selected, so the menus and the toolbar have something
  /// to act on instead of every row carrying its own controls.
  @State private var selection: Set<Uuid> = []

  /// What the window calls itself.
  ///
  /// A category's title is its own name, which lives on the category and
  /// not in the navigation case, so it is looked up here rather than being
  /// something `Navigation` could answer alone. Returned as a `String`
  /// because a category name is data; the fixed pages go through the
  /// catalogue on their way here.
  private var pageTitle: String {
    if case let .category(id) = model.navigation {
      guard let category = model.categories.first(where: { $0.id == id }) else { return "" }
      return Categories.name(category.name, iconKey: category.iconKey)
    }
    return model.navigation.title ?? ""
  }

  /// Sorted here rather than by the core: which column someone clicked is
  /// a question about this window, not about billing.
  @State private var sortOrder = [KeyPathComparator(\Renewal.date)]

  @State private var isAdding = false
  @State private var editing: Subscription?
  @State private var pendingDeletion: [Subscription] = []

  /// The backup waiting to be saved; present only while the save panel is
  /// up, since the JSON is read from the database at the moment it opens.
  @State private var exporting: BackupFile?
  @State private var isRestoring = false

  /// What the last restore changed, kept until the person has read it.
  @State private var restored: ImportSummary?

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
    .fileExporter(
      isPresented: Binding(
        get: { exporting != nil },
        set: {
          if !$0 {
            exporting = nil
          }
        }
      ),
      document: exporting,
      contentType: .json,
      defaultFilename: BackupFile.defaultFilename()
    ) { result in
      exporting = nil
      if case let .failure(error) = result {
        model.failure = error.localizedDescription
      }
    }
    .fileImporter(isPresented: $isRestoring, allowedContentTypes: [.json]) { result in
      switch result {
      case let .success(url):
        do {
          let json = try BackupFile.read(contentsOf: url)
          restored = model.restore(fromJSON: json)
        } catch {
          model.failure = error.localizedDescription
        }
      case let .failure(error):
        model.failure = error.localizedDescription
      }
    }
    .alert(
      "Backup restored",
      isPresented: Binding(
        get: { restored != nil },
        set: {
          if !$0 {
            restored = nil
          }
        }
      ),
      presenting: restored
    ) { _ in
      Button("OK") { restored = nil }
    } message: { summary in
      Text(Formatting.restored(summary))
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
      if model.navigation == .overview {
        // The overview carries its own totals in its cards, so the footer
        // below would be the same numbers a second time.
        OverviewView(model: model)
      } else if model.renewals.isEmpty {
        EmptyState(model: model, add: { isAdding = true })
        Divider()
        SpendingFooter(summaries: model.summaries)
      } else {
        table
        Divider()
        SpendingFooter(summaries: model.summaries)
      }
    }
    .navigationTitle(pageTitle)
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
    // What the menu bar acts on: whatever this window has selected.
    .focusedSceneValue(\.subscriptionActions, actions)
    // And what it acts on when the command is about the whole database.
    .focusedSceneValue(\.backupActions, backupActions)
  }

  /// The commands the menus offer for the database rather than a selection.
  ///
  /// Exporting reads the database at the moment the panel opens rather than
  /// when it is dismissed, so what is saved is what was on screen when the
  /// person asked for it.
  private var backupActions: BackupActions {
    BackupActions(
      export: {
        if let json = model.backupJSON() {
          exporting = BackupFile(json: json)
        }
      },
      restore: { isRestoring = true }
    )
  }

  /// The commands the menus offer for the window's own selection.
  private var actions: SubscriptionActions {
    actions(for: selection)
  }

  /// The commands that apply to a given selection, left `nil` when it
  /// gives them nothing to do - which is what greys a menu item out.
  private func actions(for ids: Set<Uuid>) -> SubscriptionActions {
    let chosen = subscriptions(for: ids)
    let active = chosen.filter { $0.status == .active }
    let archived = chosen.filter { $0.status == .archived }
    return SubscriptionActions(
      add: { isAdding = true },
      edit: chosen.count == 1 ? { editing = chosen.first } : nil,
      archive: active.isEmpty ? nil : { active.forEach { model.setArchived($0, true) } },
      restore: archived.isEmpty ? nil : { archived.forEach { model.setArchived($0, false) } },
      delete: chosen.isEmpty ? nil : { pendingDeletion = chosen }
    )
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
        // Trailing, so the amounts line up on their last digit. Led out
        // from the left they cannot: the symbol in front runs from one
        // character to three, and every row starts somewhere else.
        .frame(maxWidth: .infinity, alignment: .trailing)
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
          Text(Formatting.relative(renewal.date, from: model.referenceDay))
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

  /// The same commands the menu bar offers, for a right-click.
  ///
  /// Built from the selection the click implies rather than from the
  /// window's own, since clicking an unselected row acts on that row.
  @ViewBuilder
  private func menuItems(for ids: Set<Uuid>) -> some View {
    let acting = actions(for: ids)
    if let edit = acting.edit {
      Button("Edit…", action: edit)
    }
    if let archive = acting.archive {
      Button("Archive", action: archive)
    }
    if let restore = acting.restore {
      Button("Restore", action: restore)
    }
    if let delete = acting.delete {
      Button("Delete…", role: .destructive, action: delete)
    }
  }

  private func subscriptions(for ids: Set<Uuid>) -> [Subscription] {
    model.renewals.filter { ids.contains($0.id) }.map(\.subscription)
  }

  /// Asked for by hand: this is built in Swift rather than written as a
  /// `Text`, so nothing extracts it into the catalogue on its own.
  private var deletionTitle: String {
    guard pendingDeletion.count == 1, let only = pendingDeletion.first else {
      return String(localized: "Delete \(pendingDeletion.count) subscriptions?")
    }
    return String(localized: "Delete \(only.name)?")
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
    if model.navigation == .subscriptions, (model.counts[.archived] ?? 0) > 0 {
      ContentUnavailableView {
        Label("Nothing active", systemImage: "archivebox")
      } description: {
        Text("Everything here is archived. Show it to restore or remove it.")
      } actions: {
        Button("Show Archived") { model.navigation = .archived }
        Button("Add Subscription", action: add)
      }
    } else if case .category = model.navigation {
      ContentUnavailableView(
        "Nothing filed here",
        systemImage: "tag",
        description: Text("A subscription lands here once it is given this category.")
      )
    } else if model.navigation == .archived {
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
