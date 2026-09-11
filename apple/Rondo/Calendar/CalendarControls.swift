import SwiftUI

/// Back a span, to this one, forward a span.
///
/// What the arrows page by follows what is on screen: months at month
/// scale, years at year scale. One control rather than two, because the
/// gesture is the same one and only the stride differs.
struct CalendarStepper: View {
  let model: SubscriptionsModel

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    // Two points apart, so the three read as one control rather than as
    // three buttons that happen to be near each other.
    HStack(spacing: 2) {
      step(
        -1,
        symbol: "chevron.left",
        help: String(localized: "Back", bundle: bundle, locale: locale,
                     comment: "Pages the calendar to the previous month or year")
      )
      StepperButton(help: nil) {
        model.showCalendarToday()
      } label: {
        Text(verbatim: model.calendarScale.todayTitle)
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textSecondary)
          .lineLimit(1)
          .padding(.horizontal, 9)
          .frame(height: 22)
      }
      step(
        1,
        symbol: "chevron.right",
        help: String(localized: "Forward", bundle: bundle, locale: locale,
                     comment: "Pages the calendar to the next month or year")
      )
    }
  }

  private func step(_ count: Int, symbol: String, help: String) -> some View {
    StepperButton(help: help) {
      model.stepCalendar(by: count)
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.textSecondary)
        .frame(width: 24, height: 22)
    }
  }
}

/// One of the three small controls that page the calendar.
///
/// Its own view so it can hold hover state: these light up under the
/// pointer the way a menu bar row does, and a `@State` per button is the
/// only way each knows whether the pointer is over *it*.
private struct StepperButton<Label: View>: View {
  let help: String?
  let action: () -> Void
  @ViewBuilder var label: Label

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      label
        .contentShape(Rectangle())
        .background(
          isHovering ? Color.hoverBackground : .clear,
          in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(help ?? "")
  }
}

/// Month or year.
///
/// The same data at two scales rather than two pages, so it is a segmented
/// control and the sidebar gains no second entry.
///
/// Drawn from the design's own numbers rather than left to
/// `.pickerStyle(.segmented)`, for the same reason the Add button is: the
/// system control brings its own metrics and its own accent. In the
/// toolbar it came out as a grey capsule swallowing the selected word with
/// no track around the pair, which matched nothing else on the window.
struct CalendarScalePicker: View {
  let model: SubscriptionsModel

  var body: some View {
    HStack(spacing: 0) {
      ForEach(CalendarScale.allCases) { scale in
        segment(scale)
      }
    }
    .padding(2)
    .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control,
                                                            style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(String(localized: "Scale", bundle: Localization.bundle,
                               locale: Localization.locale,
                               comment: "Accessibility label for the month/year switch"))
  }

  private func segment(_ scale: CalendarScale) -> some View {
    CalendarScaleSegment(
      title: scale.title,
      isSelected: model.calendarScale == scale
    ) {
      model.setCalendarScale(scale)
    }
  }
}

/// One word in the scale switch.
///
/// Its own view to hold hover state, the same as the stepper's buttons:
/// everything else on this bar lights up under the pointer, and a control
/// that does not reads as decoration rather than as something to press.
private struct CalendarScaleSegment: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Text(verbatim: title)
        .font(Theme.Font.caption)
        .fontWeight(isSelected ? .medium : .regular)
        .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, 11)
        .padding(.vertical, 3)
        // The fill is drawn behind the word rather than around it, so the
        // lift under the selected segment stays under it: `.shadow` on the
        // label shadows everything in the label, the text included, and the
        // word came out looking smudged rather than raised.
        .background {
          if isSelected {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .fill(Color.surfaceRaised)
              .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
          } else if isHovering {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .fill(Color.hoverBackground)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}
