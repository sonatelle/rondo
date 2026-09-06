import SwiftUI

extension ToolbarContent {
  /// Drops the container macOS 26 draws behind a toolbar item.
  ///
  /// From that release the system puts a rounded glass panel behind every
  /// item, which is right for the stock controls and wrong for a control
  /// that already has its own shape: the blue button came out sitting on a
  /// lilac slab, and the search field on a white capsule.
  ///
  /// A no-op on macOS 14 and 15, which draw no such thing.
  @ToolbarContentBuilder
  func plainToolbarItem() -> some ToolbarContent {
    if #available(macOS 26.0, *) {
      sharedBackgroundVisibility(.hidden)
    } else {
      self
    }
  }
}

/// The toolbar's search field, drawn from the design's own numbers.
///
/// Not `.searchable`, which is the obvious choice and the wrong one here:
/// macOS 26 draws that as a tall white capsule with a shadow, and beside a
/// row of flat chips and pills it was the one control from a different
/// drawing. Its keyboard shortcut is the part worth keeping, and that is
/// re-hung on the Find command in the menu bar rather than lost.
///
/// The clear button appears only when there is something to clear. A
/// search left on is the sort of thing that makes a list look empty for
/// reasons nobody can see, so there has to be an obvious way out of it.
struct SearchField: View {
  @Binding var text: String

  /// Owned by the window, so the Find command can put the cursor here.
  @FocusState.Binding var isFocused: Bool

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return HStack(spacing: Theme.Space.s) {
      // The magnifier the design's static mock leaves out. A field with a
      // placeholder says what to type in it; the symbol says what the field
      // is at a glance, from across the window, before anybody reads it.
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.textFaint)
      TextField(
        String(localized: "Search subscriptions", bundle: bundle, locale: locale,
               comment: "The toolbar's search field"),
        text: $text
      )
      .textFieldStyle(.plain)
      .font(Theme.Font.body)
      .focused($isFocused)
      // Enter is the shortest way out of a field somebody is done with.
      .onSubmit { isFocused = false }
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(Color.textFaint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Clear the search", bundle: bundle, locale: locale,
                     comment: "Tooltip on the search field's clear button"))
      }
    }
    .padding(.horizontal, Theme.Space.m)
    .frame(width: 170, height: 26)
    .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
  }
}
