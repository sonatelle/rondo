import SwiftUI

/// Which day the money leaves on.
///
/// The list pages answer "what am I paying for"; this answers "when". A
/// month of six rows, a charge drawn as a chip in its day, and a strip
/// above saying what the month comes to - which is the chips added up,
/// because the core folds one out of the other rather than counting twice.
struct CalendarView: View {
  let model: SubscriptionsModel

  var body: some View {
    VStack(spacing: 0) {
      CalendarSummaryStrip(model: model)
      MonthGrid(model: model)
    }
    .background(Color.surface)
  }
}

// MARK: - The strip above the grid

/// What the span on screen comes to, and what the colours in it mean.
///
/// One figure in the primary currency rather than a list per currency,
/// and a line naming whatever no rate reached: a month quietly missing two
/// charges looks exactly like a cheaper month.
struct CalendarSummaryStrip: View {
  let model: SubscriptionsModel

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    HStack(alignment: .top, spacing: 26) {
      figure(
        String(localized: "Total", bundle: bundle, locale: locale,
               comment: "Calendar strip: what the span on screen comes to"),
        totalText
      )

      figure(
        String(localized: "Charges", bundle: bundle, locale: locale,
               comment: "Calendar strip: how many charges fall in the span"),
        "\(model.calendarCharges.count)"
      )
      // A rule between the figures rather than around them, so the strip
      // reads as one row divided rather than as a row of boxes.
      .padding(.leading, 26)
      .overlay(alignment: .leading) {
        Rectangle().fill(Color.separatorLine).frame(width: 0.5)
      }

      // Only when the figure covers less than the count beside it claims,
      // which is the one thing a reader cannot spot for themselves.
      if let missing = model.calendarTotal?.unconvertedCurrencies, !missing.isEmpty {
        Text(verbatim: String(localized: "no rate for \(missing.joined(separator: ", "))",
                              bundle: bundle, locale: locale,
                              comment: "Under a window total, naming what it leaves out"))
          .font(Theme.Font.footnote)
          .foregroundStyle(Color.danger)
      }

      Spacer(minLength: Theme.Space.card)

      UrgencyLegend()
    }
    .padding(.horizontal, Theme.Space.section)
    .padding(.vertical, Theme.Space.xxl)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color.separatorLine).frame(height: 0.5)
    }
  }

  /// A label over a figure, which is the shape both halves of the strip
  /// take.
  private func figure(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: title)
        .font(Theme.Font.groupTitle)
        .foregroundStyle(Color.textMuted)
        .lineLimit(1)
      Text(verbatim: value)
        .font(.system(size: 19, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color.textPrimary)
        .lineLimit(1)
    }
  }

  /// The span's total, or a dash when nothing converted.
  ///
  /// A dash rather than a zero: a month whose charges could not be
  /// converted has not cost nothing, and printing 0 would say it had.
  private var totalText: String {
    guard let total = model.calendarTotal, total.convertedChargeCount > 0 else {
      return "—"
    }
    return Formatting.amount(total.total, currency: total.currency)
  }
}

/// What the three colours in the grid mean.
///
/// Spelled out because the colours carry the only meaning on this page
/// that is not written in words, and "red" is not self-explanatory on a
/// calendar where every cell is a date.
private struct UrgencyLegend: View {
  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return HStack(spacing: Theme.Space.xxl) {
      item(.urgent, String(localized: "Within 3 days", bundle: bundle, locale: locale,
                           comment: "Calendar legend: the most urgent band"))
      item(.soon, String(localized: "Within 7 days", bundle: bundle, locale: locale,
                         comment: "Calendar legend: the middle band"))
      item(.distant, String(localized: "Later", bundle: bundle, locale: locale,
                            comment: "Calendar legend: everything further off"))
    }
  }

  private func item(_ urgency: Urgency, _ title: String) -> some View {
    HStack(spacing: Theme.Space.s) {
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .fill(urgency.marker)
        .frame(width: 8, height: 8)
      Text(verbatim: title)
        .font(.system(size: 12))
        .foregroundStyle(Color.textSecondary)
        .lineLimit(1)
    }
  }
}

// MARK: - The month

/// Six weeks of days, laid out the way the week-start setting says.
private struct MonthGrid: View {
  let model: SubscriptionsModel

  /// Which day a week starts on. The same preference the date field's
  /// popover reads: a week starting on Monday there and on Sunday here
  /// would be two different calendars.
  @AppStorage(Preference.firstWeekday) private var firstWeekday = 2

  /// Always six rows, so paging between a month that needs five and one
  /// that needs six does not make the grid jump under the pointer.
  private static let weeks = 6

  var body: some View {
    VStack(spacing: Theme.Space.s) {
      weekdays
      VStack(spacing: Theme.Space.s) {
        ForEach(0 ..< Self.weeks, id: \.self) { week in
          HStack(spacing: Theme.Space.s) {
            ForEach(0 ..< 7, id: \.self) { weekday in
              DayCell(
                day: days[week * 7 + weekday],
                isThisMonth: isThisMonth(days[week * 7 + weekday]),
                today: model.referenceDay,
                charges: charges[days[week * 7 + weekday]] ?? [],
                names: names,
                primaryCurrency: model.primaryCurrency
              )
            }
          }
        }
      }
      .frame(maxHeight: .infinity)
    }
    .padding(.horizontal, Theme.Space.card)
    .padding(.top, Theme.Space.m)
    .padding(.bottom, Theme.Space.card)
  }

  private var calendar: Calendar {
    var calendar = Calendar.current
    calendar.firstWeekday = firstWeekday
    calendar.locale = Localization.locale
    return calendar
  }

  private var weekdays: some View {
    // Standalone symbols: some languages inflect a weekday differently
    // inside a sentence than as a heading.
    let symbols = calendar.veryShortStandaloneWeekdaySymbols
    let ordered = (0 ..< 7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    return HStack(spacing: Theme.Space.s) {
      ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
        Text(verbatim: symbol)
          .font(Theme.Font.groupTitle)
          .foregroundStyle(Color.textMuted)
          .lineLimit(1)
          .frame(maxWidth: .infinity)
      }
    }
  }

  /// Forty-two days starting on the row the first of the month falls in.
  private var days: [CivilDate] {
    guard let anchor = Formatting.parseCivilDate(model.calendarAnchor),
          let week = calendar.dateInterval(of: .weekOfMonth, for: anchor)
    else { return Array(repeating: model.calendarAnchor, count: Self.weeks * 7) }
    return (0 ..< Self.weeks * 7).map { offset in
      guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else {
        return model.calendarAnchor
      }
      return Formatting.civilDate(from: day)
    }
  }

  private func isThisMonth(_ day: CivilDate) -> Bool {
    guard let date = Formatting.parseCivilDate(day),
          let anchor = Formatting.parseCivilDate(model.calendarAnchor)
    else { return false }
    return calendar.isDate(date, equalTo: anchor, toGranularity: .month)
  }

  /// The span's charges filed under the day each falls on.
  ///
  /// Grouped once per redraw rather than scanned per cell: forty-two cells
  /// each filtering the whole list is the same work forty-two times.
  private var charges: [CivilDate: [DatedCharge]] {
    Dictionary(grouping: model.calendarCharges, by: \.date)
  }

  /// Subscription names by id, so a chip can say what it is for.
  ///
  /// From `allRenewals` rather than the active list: a charge in a past
  /// month may belong to something archived since, and a chip reading
  /// "(unknown) ¥21" would be worse than the name.
  private var names: [Uuid: String] {
    Dictionary(
      model.allRenewals.map { ($0.subscription.id, $0.subscription.name) },
      uniquingKeysWith: { first, _ in first }
    )
  }
}

/// One day, with whatever falls due on it.
private struct DayCell: View {
  let day: CivilDate
  let isThisMonth: Bool
  let today: CivilDate
  let charges: [DatedCharge]
  let names: [Uuid: String]
  let primaryCurrency: String

  /// How many chips a day shows before it starts counting instead.
  ///
  /// Two, because a cell is a seventh of the window's width and a sixth of
  /// what is left of its height, and a third chip is what makes the row
  /// grow rather than the cell.
  private static let chipsShown = 2

  private var isToday: Bool {
    day == today
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Space.xs) {
      number
      ForEach(charges.prefix(Self.chipsShown)) { charge in
        ChargeChip(
          title: names[charge.subscriptionId] ?? "",
          charge: charge,
          today: today,
          primaryCurrency: primaryCurrency
        )
      }
      if charges.count > Self.chipsShown {
        Text(verbatim: String(
          localized: "and \(charges.count - Self.chipsShown) more",
          bundle: Localization.bundle, locale: Localization.locale,
          comment: "A day with more charges than the cell can show"
        ))
        .font(.system(size: 10.5))
        .foregroundStyle(Color.textFaint)
        .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Theme.Space.m)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    // The lift the design gives a day in this month, and only those: the
    // days either side are sunk rather than raised, so the month itself is
    // what the grid reads as.
    .shadow(color: isThisMonth ? .black.opacity(0.05) : .clear, radius: 1, y: 1)
    .overlay {
      if isToday {
        RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
          .strokeBorder(Color.brand, lineWidth: 2)
      }
    }
  }

  private var number: some View {
    HStack(spacing: 5) {
      Text(verbatim: dayOfMonth)
        .font(.system(size: isToday ? 11.5 : 12, weight: weight))
        .monospacedDigit()
        .foregroundStyle(numberColour)
        .frame(minWidth: 19, minHeight: 19)
        .background(isToday ? Color.brand : .clear, in: Circle())
      // Said in words beside the ring, not left to the colour alone: a
      // blue circle is a selection in most interfaces, and this is not one
      // - nothing here is selectable.
      if isToday {
        Text(verbatim: String(localized: "Today", bundle: Localization.bundle,
                              locale: Localization.locale,
                              comment: "Brings the calendar back to this month"))
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(Color.brand)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
  }

  private var weight: Font.Weight {
    if isToday {
      return .semibold
    }
    return charges.isEmpty ? .regular : .semibold
  }

  private var dayOfMonth: String {
    guard let date = Formatting.parseCivilDate(day) else { return "" }
    return "\(Calendar.current.component(.day, from: date))"
  }

  private var numberColour: Color {
    if isToday {
      return .white
    }
    if !isThisMonth {
      return .textFaint
    }
    return charges.isEmpty ? .textSecondary : .textPrimary
  }

  /// Days either side of the month are shown rather than blanked, so the
  /// weeks stay whole - but sunk rather than raised, so the month itself
  /// is what the eye lands on.
  private var background: Color {
    isThisMonth ? .surfaceRaised : .hoverBackground
  }
}

/// One charge, as it appears inside a day.
private struct ChargeChip: View {
  let title: String
  let charge: DatedCharge
  let today: CivilDate
  let primaryCurrency: String

  var body: some View {
    let urgency = Urgency.of(charge.date, from: today)
    HStack(spacing: 5) {
      // The same colour as the legend's swatch, which is the only thing
      // that makes the legend mean anything.
      Circle()
        .fill(urgency.marker)
        .frame(width: 5, height: 5)
      // The name may be squeezed away entirely on a narrow window; the
      // amount may not, so it is the one that keeps its size.
      Text(verbatim: title)
        .lineLimit(1)
        .truncationMode(.tail)
      Text(verbatim: amountText)
        .monospacedDigit()
        .lineLimit(1)
        .layoutPriority(1)
    }
    .font(.system(size: 10.5, weight: .semibold))
    .foregroundStyle(urgency.foreground)
    .padding(.horizontal, Theme.Space.s)
    .padding(.vertical, 3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      urgency.background ?? Color.hoverBackground,
      in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous)
    )
  }

  /// The converted figure where there is one, and the billed amount where
  /// no rate reaches it - never a converted-looking number that is not.
  private var amountText: String {
    Formatting.amount(
      charge.amount,
      currency: charge.currency,
      convertedTo: primaryCurrency,
      converted: charge.converted
    ).primary
  }
}

// MARK: - Previews

#Preview("Calendar · wide") {
  CalendarView(model: PreviewData.populated())
    .frame(width: 900, height: 700)
}

#Preview("Calendar · at the window's floor") {
  CalendarView(model: PreviewData.populated())
    .frame(width: RondoWindow.minimumWidth - RondoWindow.minimumSidebarWidth,
           height: RondoWindow.minimumHeight)
}

#Preview("Calendar · nothing yet") {
  CalendarView(model: PreviewData.empty())
    .frame(width: 900, height: 700)
}
