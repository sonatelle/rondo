import SwiftUI

/// The pages, the categories, and what has been put away.
///
/// The archive sits at the foot, apart from the rest, because it is not
/// somewhere to go so much as somewhere things end up. Under it, a line
/// saying where the data lives - the one claim the app makes about itself
/// that is worth repeating where it can be seen.
struct Sidebar: View {
  @Bindable var model: SubscriptionsModel

  /// Whether the sidebar holds the keyboard focus.
  ///
  /// Asked for at launch, because until something is focused macOS draws a
  /// selected row in its unemphasized grey rather than the accent, and a
  /// window that opens showing a greyed-out selection looks like it opened
  /// wrong. Clicking a row would fix it, but nobody should have to.
  @FocusState private var focused: Bool

  var body: some View {
    List(selection: $model.navigation) {
      Section {
        row(.overview)
        row(.subscriptions, count: model.counts[.subscriptions])
      }

      if !model.categories.isEmpty {
        Section("Categories") {
          ForEach(model.categories, id: \.id) { category in
            let destination = Navigation.category(category.id)
            Label {
              Text(verbatim: Categories.name(category.name, iconKey: category.iconKey))
            } icon: {
              Image(systemName: Categories.symbol(for: category.iconKey))
                .foregroundStyle(
                  symbolColour(
                    Categories.tint(for: category.colorKey),
                    selected: model.navigation == destination
                  )
                )
            }
            .badge(model.counts[destination] ?? 0)
            .tag(destination)
          }
        }
      }

      Section {
        row(.archived, count: model.counts[.archived])
      }
    }
    .navigationSplitViewColumnWidth(min: 180, ideal: 212, max: 280)
    .focused($focused)
    // Asked for after the window has settled rather than through
    // `defaultFocus`, which the split view's detail column takes back:
    // yielding once lets that happen first and puts the focus here after.
    .task {
      await Task.yield()
      focused = true
    }
    // Pinned under the list rather than placed after the last row, so it
    // stays on the floor of the column however few entries there are and
    // does not scroll away once there are many.
    .safeAreaInset(edge: .bottom) {
      Text("Stored on this Mac · no account")
        .font(Theme.Font.footnote)
        .foregroundStyle(Color.textFaint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.l)
        .padding(.bottom, Theme.Space.m)
    }
  }

  /// What colour a sidebar symbol is drawn in.
  ///
  /// Its own colour on a plain row. On a selected one it is left to the
  /// list, which is the point: a symbol close to the accent vanishes into
  /// the fill - the blue overview icon did exactly that - and the system
  /// already knows what colour its own selected content should be. It also
  /// knows things a fixed white does not: the fill is grey rather than
  /// accent-coloured while the window is not focused, and the accent itself
  /// is the person's to change in System Settings.
  ///
  /// `listItemTint` is the modifier that ought to cover this whole job, and
  /// on a SwiftUI sidebar it does not tint at all - it left every symbol
  /// black - so the unselected half is said here.
  private func symbolColour(_ tint: Color, selected: Bool) -> AnyShapeStyle {
    selected ? AnyShapeStyle(.foreground) : AnyShapeStyle(tint)
  }

  /// One navigation entry, tinted for what it is.
  ///
  /// The icon is coloured rather than the whole row, so the text keeps
  /// reading as text at any size.
  private func row(_ destination: Navigation, count: Int? = nil) -> some View {
    Label {
      // Verbatim: the title has been through the catalogue already, and a
      // `LocalizedStringKey` would look it up a second time and find
      // nothing. A category never comes here - it has its own row.
      Text(verbatim: destination.title ?? "")
    } icon: {
      Image(systemName: destination.symbol)
        .foregroundStyle(
          symbolColour(destination.tint, selected: model.navigation == destination)
        )
    }
    .badge(count ?? 0)
    .tag(destination)
  }
}
