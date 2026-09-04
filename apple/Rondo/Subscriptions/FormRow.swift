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

/// A date, shown the way the rest of the form shows a value, with a
/// calendar behind it.
///
/// macOS's own date control is a stepper beside three little number fields.
/// It is fine for setting an alarm and wrong here: the design draws this as
/// one more field in a column of fields, and a first charge is a day
/// somebody picks off a calendar rather than a number they nudge.
///
/// The popover closes as soon as a day is chosen, since choosing one is the
/// whole reason it opened. Moving between months leaves the date alone, so
/// somebody looking for next March can go on looking.
struct DateField: View {
  @Binding var date: Date

  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      HStack(spacing: Theme.Space.s) {
        Text(Formatting.date(Formatting.civilDate(from: date)))
          .font(Theme.Font.body)
          .monospacedDigit()
          .foregroundStyle(Color.textPrimary)
          .lineLimit(1)
        Image(systemName: "calendar")
          .font(.system(size: 11))
          .foregroundStyle(Color.textFaint)
      }
      .padding(.horizontal, Theme.Space.m)
      .frame(height: 27)
      .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      DatePicker(selection: $date, displayedComponents: .date) { EmptyView() }
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding(Theme.Space.l)
        .onChange(of: date) { isPresented = false }
    }
  }
}

/// The currency an amount is recorded in.
///
/// A `Menu` rather than a `Picker`, which is a performance decision and not
/// a visual one. There are 159 codes, and a picker builds every row of its
/// list the moment the view is built: measured on this machine, that is
/// about 250ms of the sheet's opening, against 8ms for a menu, which builds
/// its items when somebody actually opens it. The form used to take a
/// visible beat to appear, and this was all of it.
///
/// The button shows the code alone. The design draws "CNY 人民币" there,
/// which reads well in Chinese and becomes "Chinese Yuan Renminbi" in
/// English - too wide for a row that also holds a price and a note. The
/// name goes in the menu, where there is room for it.
struct CurrencyMenu: View {
  @Binding var currency: String

  var body: some View {
    Menu {
      ForEach(Currencies.including(currency), id: \.self) { code in
        Button {
          currency = code
        } label: {
          if let name = Localization.locale.localizedString(forCurrencyCode: code) {
            Text(verbatim: "\(code) · \(name)")
          } else {
            Text(verbatim: code)
          }
        }
      }
    } label: {
      Text(verbatim: currency)
        .font(Theme.Font.body)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
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
