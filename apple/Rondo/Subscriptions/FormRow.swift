import SwiftUI

/// One labelled row of the subscription form.
///
/// A label of a fixed width, then whatever the row puts beside it. The row
/// lays out its own trailing content rather than being handed a "note"
/// slot, because the design does not treat them alike: "required" sits
/// against the field it qualifies, while "currencies are never converted"
/// is pushed to the far edge. One slot could only do one of those.
///
/// Centred rather than baseline-aligned. A row holds a text field, a
/// segmented control and a row of chips, and their baselines are in
/// different places; their middles are not.
struct FormRow<Content: View>: View {
  /// The label, already through the catalogue.
  ///
  /// A `String` rather than a `LocalizedStringKey`, which is the same rule
  /// the rest of the app follows: a key resolves against the system's
  /// language rather than the chosen one, so words are looked up by their
  /// caller - with `Localization.bundle` - and arrive here as text to draw.
  let label: String

  /// The gap between the row's own parts, which the design varies from 10
  /// to 14 depending on what is in the row.
  var spacing: CGFloat = Theme.Space.xl

  @ViewBuilder var content: Content

  /// The label column's width, from the design. Wide enough for the
  /// longest label in either language without wrapping.
  static var labelWidth: CGFloat {
    96
  }

  var body: some View {
    HStack(alignment: .center, spacing: spacing) {
      Text(verbatim: label)
        .font(Theme.Font.label)
        .foregroundStyle(Color.textSecondary)
        .frame(width: Self.labelWidth, alignment: .leading)
      content
    }
    .padding(.horizontal, Theme.Space.card)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A card of rows, separated by hairlines.
struct FormCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
  }
}

/// The hairline between two rows of a card.
struct FormDivider: View {
  var body: some View {
    Divider().foregroundStyle(Color.separatorLine)
  }
}

/// A text field shaped like the design's inputs.
///
/// Filling the row is the default, because most of these do; a width is
/// given only where the design fixes one - 96 points for an amount, 46 for
/// a cycle count - and those are the fields that hold numbers, so a width
/// also makes the digits tabular.
struct FormField: View {
  @Binding var text: String

  /// A fixed width, for the fields the design sizes to their contents.
  var width: CGFloat?

  /// Where the text sits in the box.
  ///
  /// An amount is read from its last digit, so money is right-aligned; a
  /// single digit in a 46-point box has no column to line up with and
  /// reads as centred instead. A field with no width is text, and text
  /// starts at the leading edge.
  var alignment: TextAlignment?

  private var resolvedAlignment: TextAlignment {
    alignment ?? (width == nil ? .leading : .trailing)
  }

  var body: some View {
    // Label-less rather than `TextField("")`: an empty string literal is
    // still a key, and it reached the catalogue as a blank entry nobody
    // could translate. The label column beside it is the label.
    TextField(text: $text) { EmptyView() }
      .textFieldStyle(.plain)
      .font(Theme.Font.body)
      .multilineTextAlignment(resolvedAlignment)
      .monospacedDigit(width != nil)
      .padding(.horizontal, 9)
      .frame(height: 27)
      .frame(width: width)
      .frame(maxWidth: width == nil ? .infinity : nil)
      .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
  }
}

/// What opens a picker: a value, and a chevron saying there are others.
///
/// The same box the provider picker uses, because they are the same thing
/// and the form reads as a column of fields rather than a column of
/// different-looking controls. This is not a `Menu`: macOS draws a
/// borderless menu as bare words with its own indicator on the leading
/// edge, and neither `menuIndicator(.hidden)` nor a background on the label
/// changes that. A button that opens a popover is drawn entirely by us.
struct PickerChip: View {
  let title: String

  /// Wide enough not to jump between a short value and a long one, but not
  /// stretched across the row: these sit beside a note.
  var minWidth: CGFloat = 92

  var body: some View {
    HStack(spacing: Theme.Space.s) {
      Text(verbatim: title)
        .font(Theme.Font.body)
        .foregroundStyle(Color.textPrimary)
        .lineLimit(1)
      Spacer(minLength: Theme.Space.xs)
      Image(systemName: "chevron.down")
        .font(.system(size: 10))
        .foregroundStyle(Color.textFaint)
    }
    .padding(.horizontal, Theme.Space.m)
    .frame(minWidth: minWidth, alignment: .leading)
    .frame(height: 29)
    .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    .contentShape(Rectangle())
  }
}

/// One choice inside a picker's popover: what it is called, whether it is
/// the one chosen, and - where the list allows it - a way to remove it.
struct PickerRow<Trailing: View>: View {
  let title: String
  let isChosen: Bool
  let choose: () -> Void
  @ViewBuilder var trailing: Trailing

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: Theme.Space.s) {
      Button(action: choose) {
        HStack(spacing: Theme.Space.l) {
          Text(verbatim: title)
            .font(Theme.Font.body)
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
          Spacer(minLength: Theme.Space.xs)
          if isChosen {
            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Color.brand)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      // Shown on hover rather than always: a row of delete buttons reads
      // as a page about deleting things, and this is a page about choosing
      // one. The row keeps its width either way, so nothing shifts.
      trailing
        .opacity(isHovering ? 1 : 0)
    }
    .padding(.horizontal, Theme.Space.m)
    .padding(.vertical, Theme.Space.s)
    .background(
      isChosen ? Color.surfaceRaised : (isHovering ? Color.hoverBackground : .clear),
      in: RoundedRectangle(cornerRadius: Theme.Radius.sidebarItem)
    )
    .onHover { isHovering = $0 }
  }
}

extension PickerRow where Trailing == EmptyView {
  init(title: String, isChosen: Bool, choose: @escaping () -> Void) {
    self.init(title: title, isChosen: isChosen, choose: choose) { EmptyView() }
  }
}

/// The currency an amount is recorded in.
///
/// A button and a popover, the shape every other picker in this form takes.
/// It is also what keeps the sheet quick: there are 159 codes, and a
/// `Picker` builds every row of its list the moment the view is built -
/// measured on this machine, about 250ms of the sheet's opening. A popover
/// builds its contents when somebody opens it, which is 2ms.
///
/// Searchable, because 159 is more than anybody scrolls: three letters of
/// either the code or the currency's name is faster than any list.
///
/// The button shows the code alone. The design draws "CNY 人民币" there,
/// which reads well in Chinese and becomes "Chinese Yuan Renminbi" in
/// English - too wide for a row that also holds a price and a note. The
/// name goes in the list, where there is room for it.
struct CurrencyPicker: View {
  @Binding var currency: String

  @State private var isPresented = false
  @State private var query = ""

  var body: some View {
    Button {
      isPresented = true
    } label: {
      PickerChip(title: currency, minWidth: 84)
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      panel
    }
  }

  private var panel: some View {
    VStack(spacing: 0) {
      TextField(
        String(localized: "Search currencies", bundle: Localization.bundle,
               locale: Localization.locale, comment: "The currency picker's search field"),
        text: $query
      )
      .textFieldStyle(.plain)
      .font(Theme.Font.body)
      .padding(.horizontal, Theme.Space.l)
      .frame(height: 29)
      .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
      .padding(Theme.Space.l)

      Divider().foregroundStyle(Color.separatorLine)

      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(matches, id: \.self) { code in
            PickerRow(title: label(code), isChosen: code == currency) {
              currency = code
              isPresented = false
            }
          }
        }
        .padding(Theme.Space.m)
      }
      // A fixed height rather than a maximum: a popover measures itself
      // once, so a list that grew back after a search was cleared would
      // stay clipped to the shorter one's height.
      .frame(height: 280)
    }
    .frame(width: 260)
    .background(Color.surface)
    .multilineTextAlignment(.leading)
  }

  /// Matched on the code and on the name, since somebody hunting for yen
  /// may know either. Case-folded, so "jpy" finds JPY.
  private var matches: [String] {
    let codes = Currencies.including(currency)
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return codes }
    return codes.filter { label($0).lowercased().contains(needle) }
  }

  /// The code, and the currency's name where the reader's language has one.
  private func label(_ code: String) -> String {
    guard let name = Localization.locale.localizedString(forCurrencyCode: code) else {
      return code
    }
    return "\(code) · \(name)"
  }
}

/// A note beside a control: "required", or a sentence about what the field
/// means.
struct FormNote: View {
  /// The note, already through the catalogue; see `FormRow.label`.
  let text: String

  /// The design uses two greys here: a fainter one for a word like
  /// "optional", a darker one for a sentence that is telling you something.
  var speaking = false

  var body: some View {
    Text(verbatim: text)
      .font(speaking ? Theme.Font.caption : Theme.Font.footnote)
      .foregroundStyle(speaking ? Color.textMuted : Color.textFaint)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// A capsule that can be picked, as the design draws a category.
struct FormChip: View {
  let title: String
  var symbol: String?
  var tint: Color?
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: Theme.Space.xs) {
        if let symbol {
          Image(systemName: symbol)
            .font(.system(size: 10))
            .foregroundStyle(isSelected ? Color.white : (tint ?? Color.textSecondary))
        }
        Text(verbatim: title)
          .font(Theme.Font.caption)
          .fontWeight(isSelected ? .medium : .regular)
          .foregroundStyle(isSelected ? Color.white : Color.textPrimary)
      }
      .padding(.horizontal, 11)
      .padding(.vertical, 4)
      .background(isSelected ? Color.brand : Color.hoverBackground, in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

private extension View {
  /// Applies `monospacedDigit` only when asked, so a name field is not
  /// tabular for no reason.
  @ViewBuilder
  func monospacedDigit(_ enabled: Bool) -> some View {
    if enabled {
      monospacedDigit()
    } else {
      self
    }
  }
}
