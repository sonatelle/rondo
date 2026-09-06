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

  /// What has been typed into the toolbar's search field.
  ///
  /// It narrows this window's view and nothing else: the sidebar's counts,
  /// the menu bar item and every total go on describing the whole database.
  /// A search is a way of looking, not a way of changing what is there.
  @State private var searchText = ""

  /// Whether the cursor is in the search field, so ⌘F can put it there.
  @FocusState private var searchFocused: Bool

  /// Which shop and which currency the list is narrowed to.
  ///
  /// Both are cleared when the page changes, along with the search: a page
  /// that opens already narrowed by something chosen on another one looks
  /// like a page with fewer subscriptions than it has.
  @State private var channelFilter: ChannelFilter = .any
  @State private var currencyFilter: String?

  /// The rows this page is showing, after the search has narrowed them.
  ///
  /// Matched on the name and on the account, which are the two things
  /// somebody knows when they are hunting: what it is called, and which
  /// address it bills to. The category and the payment method are left out
  /// on purpose - the sidebar and the columns already sort those, and a
  /// search that also matched them would return rows whose reason for
  /// matching is invisible.
  ///
  /// Case and accents are ignored, so "netflix" finds Netflix and "cafe"
  /// finds Café.
  private var matching: [Renewal] {
    let needle = searchText.trimmingCharacters(in: .whitespaces)
    return model.renewals.filter { renewal in
      let subscription = renewal.subscription
      guard channelFilter.matches(subscription) else { return false }
      guard currencyFilter == nil || subscription.currency == currencyFilter else { return false }
      guard !needle.isEmpty else { return true }
      let fields = [subscription.name, subscription.account ?? ""]
      return fields.contains {
        $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
    }
  }

  /// The channels the page's own rows were bought through, in the order the
  /// segmented control in the form offers them, and "nobody said" last if
  /// anything is missing one.
  ///
  /// Taken from the rows before the filters narrow them, so choosing one
  /// never empties the list of choices it was chosen from.
  private var offeredChannels: [ChannelFilter] {
    let present = Set(model.renewals.map(\.subscription.channel))
    var offered: [ChannelFilter] = [Channel.appStore, .googlePlay, .web, .other]
      .filter { present.contains($0) }
      .map { ChannelFilter.bought($0) }
    if present.contains(nil) {
      offered.append(.unrecorded)
    }
    return offered
  }

  /// The currencies the page's own rows are charged in, by code.
  private var offeredCurrencies: [String] {
    Array(Set(model.renewals.map(\.subscription.currency))).sorted()
  }

  /// How many the page is showing, beside its title.
  ///
  /// The subtitle macOS puts next to a window title, rather than a line of
  /// our own drawing: the design's header strip is the titlebar - the
  /// traffic lights sit in it - so this is where it belongs.
  ///
  /// It says what the rows are, not only how many, because the same number
  /// means different things on different pages: eight being paid for is not
  /// eight that were stopped. The overview has no list to count, so it says
  /// nothing at all rather than counting something arbitrary.
  private var pageCount: String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    let count = matching.count
    return switch model.navigation {
    case .overview: ""
    case .archived:
      String(localized: "\(count) archived", bundle: bundle, locale: locale,
             comment: "Beside the title: how many subscriptions were stopped")
    case .subscriptions, .category:
      String(localized: "\(count) active", bundle: bundle, locale: locale,
             comment: "Beside the title: how many subscriptions are being paid for")
    }
  }

  /// Sorted here rather than by the core: which column someone clicked is
  /// a question about this window, not about billing.
  @State private var sortOrder = [KeyPathComparator(\SubscriptionRow.date)]

  /// Which columns are shown, and in what order.
  ///
  /// Kept per scene rather than stored: it belongs to a window the way a
  /// scroll position does, and a second window opened on the same data may
  /// reasonably be arranged differently.
  @SceneStorage("subscriptionColumns") private var columns: TableColumnCustomization<SubscriptionRow>

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
      Button(String(localized: "Delete", bundle: Localization.bundle,
                    locale: Localization.locale,
                    comment: "Confirms deleting subscriptions"), role: .destructive)
      {
        for subscription in pendingDeletion {
          model.delete(subscription)
        }
        pendingDeletion = []
      }
    } message: {
      Text(verbatim: String(
        localized: "This cannot be undone. To stop counting it but keep the record, archive it instead.",
        bundle: Localization.bundle, locale: Localization.locale,
        comment: "Under the delete confirmation"
      ))
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
      String(localized: "Backup restored", bundle: Localization.bundle,
             locale: Localization.locale, comment: "Title of the alert after an import"),
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
      Button(String(localized: "OK", bundle: Localization.bundle, locale: Localization.locale,
                    comment: "Dismisses a message")) { restored = nil }
    } message: { summary in
      Text(verbatim: Formatting.restored(summary))
    }
    .alert(
      String(localized: "Something went wrong", bundle: Localization.bundle,
             locale: Localization.locale, comment: "Title of the failure alert"),
      isPresented: Binding(
        get: { model.failure != nil },
        set: {
          if !$0 {
            model.failure = nil
          }
        }
      )
    ) {
      Button(String(localized: "OK", bundle: Localization.bundle, locale: Localization.locale,
                    comment: "Dismisses a message")) { model.failure = nil }
    } message: {
      Text(verbatim: model.failure ?? "")
    }
  }

  private var detail: some View {
    Group {
      if model.navigation == .overview {
        // The overview carries its own totals in its cards, so the footer
        // the list pages get would be the same numbers a second time.
        //
        // It also gets no search field. The design draws one in its header,
        // but the overview has no list to narrow - it is three cards and
        // the next few charges - and a field that swallows what is typed
        // and does nothing is worse than no field at all. Searching is on
        // the pages that have something to search.
        OverviewView(model: model)
      } else {
        list
      }
    }
    .navigationTitle(pageTitle)
    .navigationSubtitle(pageCount)
    .toolbar {
      // The search field first, so it sits where the design puts it: to the
      // left of the button that adds one.
      if model.navigation != .overview {
        ToolbarItem {
          SearchField(text: $searchText, isFocused: $searchFocused)
        }
        .plainToolbarItem()
      }

      ToolbarItem {
        // Filled and in the app's own blue, as the design draws it: this is
        // the one thing on the window somebody came here to do, and the
        // rest of the chrome is deliberately grey so that it stands out.
        //
        // Drawn here rather than left to `.borderedProminent`, which takes
        // the system's accent colour - whatever the person set in System
        // Settings - and the system's control metrics. Beside the pills and
        // chips on this window, which are all drawn from the design's own
        // numbers, it was the one control that did not match.
        //
        // The words, not only a plus. A "+" alone is read by whoever
        // already knows what this window is; the first time it is opened
        // there is nothing here to add one to, and the button has to say
        // what it would do.
        Button {
          isAdding = true
        } label: {
          Text(verbatim: String(localized: "Add Subscription", bundle: Localization.bundle,
                                locale: Localization.locale,
                                comment: "Toolbar button that opens the form"))
            .font(Theme.Font.body)
            .fontWeight(.medium)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Color.brand, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Add a subscription", bundle: Localization.bundle,
                     locale: Localization.locale, comment: "Tooltip on the toolbar button"))
      }
      .plainToolbarItem()
    }
    // What the menu bar acts on: whatever this window has selected.
    .focusedSceneValue(\.subscriptionActions, actions)
    // And what it acts on when the command is about the whole database.
    .focusedSceneValue(\.backupActions, backupActions)
  }

  /// The table, whatever stands in for it when there is nothing to show,
  /// and the totals under it.
  private var list: some View {
    VStack(spacing: 0) {
      // Offered even when nothing is filtered, so the way to narrow the
      // list is visible rather than something to discover.
      FilterBar(
        channel: $channelFilter,
        currency: $currencyFilter,
        channels: offeredChannels,
        currencies: offeredCurrencies,
        totals: model.levelledTotal(of: matching.map(\.subscription))
      )
      Divider()

      // Whatever is in the middle takes the slack, so the filters stay at
      // the top and the totals at the bottom. Left to itself a `VStack`
      // sizes to its contents and centres them, which the table hid by
      // being greedy and the empty states did not: the filter pills ended
      // up floating halfway down an empty page.
      Group {
        if matching.isEmpty, !searchText.isEmpty {
          // A search that found nothing is not an empty database, and the
          // answer to it is not "add a subscription". This is the system's
          // own way of saying so, and it quotes back what was typed.
          ContentUnavailableView.search(text: searchText)
        } else if matching.isEmpty, isFiltered {
          // Filtered down to nothing, which is again not an empty database.
          // The way out is the filters themselves, so the button clears them.
          narrowedToNothing
        } else if matching.isEmpty {
          EmptyState(model: model, add: { isAdding = true })
        } else {
          table
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // A page opened with another page's filters still on looks like a page
    // with fewer subscriptions than it has.
    .onChange(of: model.navigation) { _, _ in
      searchText = ""
      channelFilter = .any
      currencyFilter = nil
    }
  }

  private var isFiltered: Bool {
    channelFilter != .any || currencyFilter != nil
  }

  private var narrowedToNothing: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return ContentUnavailableView {
      Label {
        Text(verbatim: String(localized: "Nothing matches these filters", bundle: bundle,
                              locale: locale, comment: "Empty state: the filters left no rows"))
      } icon: {
        Image(systemName: "line.3.horizontal.decrease.circle")
      }
    } description: {
      Text(verbatim: String(localized: "There are subscriptions here, but none of this kind.",
                            bundle: bundle, locale: locale,
                            comment: "Under the filtered-to-nothing state"))
    } actions: {
      Button(String(localized: "Clear filters", bundle: bundle, locale: locale,
                    comment: "Puts the filters back to showing everything"))
      {
        channelFilter = .any
        currencyFilter = nil
      }
    }
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
      // Absent on the overview, which has no search field to focus.
      find: model.navigation == .overview ? nil : { searchFocused = true },
      edit: chosen.count == 1 ? { editing = chosen.first } : nil,
      archive: active.isEmpty ? nil : { active.forEach { model.setArchived($0, true) } },
      restore: archived.isEmpty ? nil : { archived.forEach { model.setArchived($0, false) } },
      delete: chosen.isEmpty ? nil : { pendingDeletion = chosen }
    )
  }

  /// The whole list, with what the form now collects spread across it.
  ///
  /// Seven columns is more than fits at the window's floor, so they can be
  /// hidden and reordered: a table is the one place macOS lets somebody
  /// decide that for themselves, and deciding for them which of the seven
  /// matters would be guessing. The name is the exception - a row with no
  /// name is not a row anybody can read.
  ///
  /// Each column is its own property rather than seven of them written out
  /// inside the `Table`. Written inline, the compiler gave up on the whole
  /// expression: "unable to type-check in reasonable time".
  private var table: some View {
    Table(rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
      nameColumn
      channelColumn
      paymentColumn
      priceColumn
      cycleColumn
      totalColumn
      nextChargeColumn
    }
    .contextMenu(forSelectionType: Uuid.self) { ids in
      menuItems(for: ids)
    } primaryAction: { ids in
      editing = subscriptions(for: ids).first
    }
  }

  /// What the table sorts and draws.
  ///
  /// Flattened out of the renewal, the payment methods and the totals
  /// rather than each cell asking for what it needs. A `Table` given a sort
  /// order sorts by key paths into its row, and two of these columns -
  /// which card paid, and what it has cost - are answers held beside the
  /// subscription rather than on it. Assembled here, they are ordinary
  /// fields and every column sorts the same way.
  private var rows: [SubscriptionRow] {
    let methods = model.paymentMethodsByID
    return matching.map { renewal in
      let subscription = renewal.subscription
      let category = model.categories.first { $0.id == subscription.categoryId }
      let total = model.totals[subscription.id]
      return SubscriptionRow(
        renewal: renewal,
        // The account and the category read as one line under the name;
        // either may be missing, and the separator goes with it.
        detail: [
          subscription.account,
          category.map { Categories.name($0.name, iconKey: $0.iconKey) },
        ].compactMap(\.self).joined(separator: " · "),
        channel: subscription.channel?.title ?? "",
        paymentMethod: subscription.paymentMethodId
          .flatMap { methods[$0].map { PaymentMethods.name($0.name) } } ?? "",
        total: total.map { Formatting.amount($0.total, currency: $0.currency) } ?? "",
        totalValue: total.flatMap { Formatting.decimal($0.total) } ?? 0
      )
    }
    .sorted(using: sortOrder)
  }

  private typealias Column = TableColumnContent<SubscriptionRow,
    KeyPathComparator<SubscriptionRow>>

  private var nameColumn: some Column {
    TableColumn(heading("Name", "Table column"), value: \.name) { row in
      identity(row)
    }
    .width(min: 170, ideal: 260)
    .customizationID("name")
    .disabledCustomizationBehavior(.visibility)
  }

  private var channelColumn: some Column {
    TableColumn(heading("Bought through", "Table column: where it was bought"),
                value: \.channel)
    { row in
      secondary(row.channel)
    }
    .width(min: 76, ideal: 86)
    .customizationID("channel")
  }

  private var paymentColumn: some Column {
    TableColumn(heading("Paid with", "Table column: which card or account pays"),
                value: \.paymentMethod)
    { row in
      secondary(row.paymentMethod)
    }
    .width(min: 90, ideal: 118)
    .customizationID("payment")
  }

  private var priceColumn: some Column {
    TableColumn(heading("Price", "Table column"), value: \.amountValue) { row in
      // Trailing, so the amounts line up on their last digit. Led out from
      // the left they cannot: the symbol in front runs from one character
      // to three, and every row starts somewhere else.
      figure(Formatting.amount(row.renewal.subscription.amount,
                               currency: row.renewal.subscription.currency),
             faded: false)
    }
    .width(min: 84, ideal: 100)
    .customizationID("price")
  }

  private var cycleColumn: some Column {
    TableColumn(heading("Cycle", "Table column"), value: \.cycleDays) { row in
      secondary(row.renewal.cycleDescription)
    }
    .width(min: 70, ideal: 110)
    .customizationID("cycle")
  }

  private var totalColumn: some Column {
    TableColumn(heading("Total", "Table column: what it has cost since the first charge"),
                value: \.totalValue)
    { row in
      figure(row.total, faded: true)
    }
    .width(min: 76, ideal: 92)
    .customizationID("total")
  }

  private var nextChargeColumn: some Column {
    TableColumn(heading("Next charge", "Table column"), value: \.date) { row in
      nextCharge(row.renewal)
    }
    .width(min: 100, ideal: 120)
    .customizationID("next")
  }

  /// A column heading, through the catalogue.
  private func heading(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
    String(localized: key, bundle: Localization.bundle, locale: Localization.locale,
           comment: comment)
  }

  /// A word in a column that is not the row's own name.
  private func secondary(_ text: String) -> some View {
    Text(verbatim: text)
      .foregroundStyle(.secondary)
      .lineLimit(1)
  }

  /// An amount, read from its last digit.
  private func figure(_ text: String, faded: Bool) -> some View {
    Text(verbatim: text)
      .monospacedDigit()
      .foregroundStyle(faded ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
      .frame(maxWidth: .infinity, alignment: .trailing)
      .lineLimit(1)
  }

  /// When it falls, as the pill the overview draws.
  private func nextCharge(_ renewal: Renewal) -> some View {
    HStack(spacing: 0) {
      Spacer(minLength: 0)
      UrgencyBadge(date: renewal.date, reference: model.referenceDay)
    }
  }

  /// The mark, the name, and the line under it that says whose account it
  /// is and what it is filed under.
  ///
  /// Two things in one column because they answer one question - which
  /// subscription is this - and because an account is only ever read next
  /// to the name it belongs to.
  private func identity(_ row: SubscriptionRow) -> some View {
    HStack(spacing: Theme.Space.m) {
      ServiceMark(name: row.name, side: 26)
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 6) {
          Text(verbatim: row.name)
            .lineLimit(1)
          if row.renewal.subscription.status == .archived {
            Text(verbatim: String(localized: "Archived", bundle: Localization.bundle,
                                  locale: Localization.locale,
                                  comment: "Marks a row that is no longer counted"))
              .font(.caption2)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.quaternary, in: Capsule())
          }
        }
        if !row.detail.isEmpty {
          Text(verbatim: row.detail)
            .font(Theme.Font.footnote)
            .foregroundStyle(Color.textMuted)
            .lineLimit(1)
        }
      }
    }
  }

  /// The same commands the menu bar offers, for a right-click.
  ///
  /// Built from the selection the click implies rather than from the
  /// window's own, since clicking an unselected row acts on that row.
  @ViewBuilder
  private func menuItems(for ids: Set<Uuid>) -> some View {
    let acting = actions(for: ids)
    let bundle = Localization.bundle
    let locale = Localization.locale
    if let edit = acting.edit {
      Button(String(localized: "Edit…", bundle: bundle, locale: locale,
                    comment: "Context menu command"), action: edit)
    }
    if let archive = acting.archive {
      Button(String(localized: "Archive", bundle: bundle, locale: locale,
                    comment: "Context menu command"), action: archive)
    }
    if let restore = acting.restore {
      Button(String(localized: "Restore", bundle: bundle, locale: locale,
                    comment: "Context menu command: un-archive"), action: restore)
    }
    if let delete = acting.delete {
      Button(String(localized: "Delete…", bundle: bundle, locale: locale,
                    comment: "Context menu command"),
             role: .destructive, action: delete)
    }
  }

  private func subscriptions(for ids: Set<Uuid>) -> [Subscription] {
    model.renewals.filter { ids.contains($0.id) }.map(\.subscription)
  }

  /// Asked for by hand: this is built in Swift rather than written as a
  /// `Text`, so nothing extracts it into the catalogue on its own.
  private var deletionTitle: String {
    guard pendingDeletion.count == 1, let only = pendingDeletion.first else {
      return String(localized: "Delete \(pendingDeletion.count) subscriptions?",
                    bundle: Localization.bundle, locale: Localization.locale,
                    comment: "Confirmation title for several at once")
    }
    return String(localized: "Delete \(only.name)?", bundle: Localization.bundle,
                  locale: Localization.locale, comment: "Confirmation title for one")
  }
}

/// One line of the table, with everything it draws already worked out.
///
/// A view model, which this app otherwise does without: the rest of the
/// interface reads the core's records directly, and a second shape of the
/// same data is usually one more thing to keep true. A sortable table earns
/// the exception. `Table` sorts by key paths into its row, so a column can
/// only sort by something the row *has* - and "which card paid for it" and
/// "what it has cost" are held beside the subscription rather than on it.
/// Looked up in the cell they would draw fine and refuse to sort.
///
/// It carries the renewal rather than copying every field out of it, so
/// this cannot drift from what the core said.
struct SubscriptionRow: Identifiable {
  let renewal: Renewal

  /// The account and the category, as one line under the name.
  let detail: String

  let channel: String
  let paymentMethod: String

  /// What it has cost since its first charge, and the same as a number to
  /// sort by: "9" is more than "10" to a string comparison.
  let total: String
  let totalValue: Decimal

  var id: Uuid {
    renewal.subscription.id
  }

  var name: String {
    renewal.subscription.name
  }

  var amountValue: Decimal {
    renewal.amountValue
  }

  var cycleDays: Int {
    renewal.cycleDays
  }

  var date: CivilDate {
    renewal.date
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
    let bundle = Localization.bundle
    let locale = Localization.locale
    if model.navigation == .subscriptions, (model.counts[.archived] ?? 0) > 0 {
      ContentUnavailableView {
        label(String(localized: "Nothing active", bundle: bundle, locale: locale,
                     comment: "Empty state: everything is archived"),
              symbol: "archivebox")
      } description: {
        Text(verbatim: String(localized: "Everything here is archived. Show it to restore or remove it.",
                              bundle: bundle, locale: locale,
                              comment: "Under the empty active list"))
      } actions: {
        Button(String(localized: "Show Archived", bundle: bundle, locale: locale,
                      comment: "Switches to the archived page"))
        {
          model.navigation = .archived
        }
        Button(String(localized: "Add Subscription", bundle: bundle, locale: locale,
                      comment: "Opens the form"), action: add)
      }
    } else if case .category = model.navigation {
      ContentUnavailableView {
        label(String(localized: "Nothing filed here", bundle: bundle, locale: locale,
                     comment: "Empty state: this category has nothing in it"),
              symbol: "tag")
      } description: {
        Text(verbatim: String(localized: "A subscription lands here once it is given this category.",
                              bundle: bundle, locale: locale,
                              comment: "Under an empty category"))
      }
    } else if model.navigation == .archived {
      ContentUnavailableView {
        label(String(localized: "Nothing archived", bundle: bundle, locale: locale,
                     comment: "Empty state: nothing has been archived"),
              symbol: "archivebox")
      } description: {
        Text(verbatim: String(localized: "Archiving keeps a subscription's record but stops counting it.",
                              bundle: bundle, locale: locale,
                              comment: "Under the empty archive"))
      }
    } else {
      ContentUnavailableView {
        label(String(localized: "No subscriptions yet", bundle: bundle, locale: locale,
                     comment: "Empty state: the database is new"),
              symbol: "repeat")
      } description: {
        Text(verbatim: String(localized: "Add one to start tracking what renews and when.",
                              bundle: bundle, locale: locale,
                              comment: "Under the empty first-run list"))
      } actions: {
        Button(String(localized: "Add Subscription", bundle: bundle, locale: locale,
                      comment: "Opens the form"), action: add)
      }
    }
  }

  /// An empty state's heading, from words already looked up.
  private func label(_ title: String, symbol: String) -> some View {
    Label {
      Text(verbatim: title)
    } icon: {
      Image(systemName: symbol)
    }
  }
}

// MARK: - Previews

// Both widths, because seven columns is the case this screen can get wrong.
// At the floor the table runs out of room and the columns it cannot fit are
// reached by scrolling sideways or hidden from the header's own menu; at a
// comfortable width they all sit at once. Seeing which is which is the
// whole point of pinning a preview to the number in `RondoWindow`.

#Preview("Subscriptions, wide") {
  ContentView(model: PreviewData.populated())
    .frame(width: 1080, height: 700)
}

#Preview("Subscriptions, at the floor") {
  ContentView(model: PreviewData.populated())
    .frame(width: RondoWindow.minimumWidth, height: RondoWindow.minimumHeight)
}
