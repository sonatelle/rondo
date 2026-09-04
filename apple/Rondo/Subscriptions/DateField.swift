import SwiftUI

/// A date, shown the way the rest of the form shows a value, with a month
/// to pick from behind it.
///
/// macOS's own date control is a stepper beside three little number fields,
/// and its graphical form is a bordered grey panel with a focus ring around
/// it. Both are fine for setting an alarm and wrong here: the design draws
/// this as one more field in a column of fields, and a first charge is a
/// day somebody picks off a calendar rather than a number they nudge. So
/// the calendar is drawn from the same tokens as everything else.
struct DateField: View {
  @Binding var date: Date

  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      HStack(spacing: Theme.Space.s) {
        Text(verbatim: Formatting.date(Formatting.civilDate(from: date)))
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
      MonthPicker(date: $date, isPresented: $isPresented)
    }
  }
}

/// One month at a time, with a day to choose.
///
/// Closes as soon as a day is chosen, since choosing one is the whole
/// reason it opened. Moving between months leaves the date alone, so
/// somebody looking for next March can go on looking.
private struct MonthPicker: View {
  @Binding var date: Date
  @Binding var isPresented: Bool

  /// Which week a row starts on, from settings. The same preference the
  /// calendar screen lays itself out by: a week that starts on Monday
  /// there and on Sunday here would be two different calendars.
  @AppStorage(Preference.firstWeekday) private var firstWeekday = 2

  /// The month on screen, which is not the chosen day: paging through the
  /// year must not change what is selected.
  @State private var visibleMonth: Date

  /// The day this is all reckoned against, read once when the popover
  /// opens rather than on every redraw.
  private let today = Date()

  init(date: Binding<Date>, isPresented: Binding<Bool>) {
    _date = date
    _isPresented = isPresented
    _visibleMonth = State(initialValue: date.wrappedValue)
  }

  /// A calendar that starts its weeks where the person asked and names its
  /// months in the language they chose.
  private var calendar: Calendar {
    var calendar = Calendar.current
    calendar.firstWeekday = firstWeekday
    calendar.locale = Localization.locale
    return calendar
  }

  var body: some View {
    VStack(spacing: Theme.Space.m) {
      header
      weekdays
      grid
    }
    .padding(Theme.Space.l)
    .frame(width: 252)
    .background(Color.surface)
  }

  private var header: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return HStack(spacing: Theme.Space.xs) {
      Text(verbatim: visibleMonth.formatted(.dateTime.year().month(.wide).locale(locale)))
        .font(Theme.Font.label)
        .fontWeight(.semibold)
        .foregroundStyle(Color.textPrimary)
        .monospacedDigit()
      Spacer(minLength: Theme.Space.s)
      step(-1, symbol: "chevron.left",
           help: String(localized: "Previous month", bundle: bundle, locale: locale,
                        comment: "Pages the calendar back"))
      Button {
        visibleMonth = today
      } label: {
        Text(verbatim: String(localized: "Today", bundle: bundle, locale: locale,
                              comment: "Brings the calendar back to this month"))
          .font(Theme.Font.footnote)
          .foregroundStyle(Color.textSecondary)
          .padding(.horizontal, Theme.Space.s)
          .frame(height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      step(1, symbol: "chevron.right",
           help: String(localized: "Next month", bundle: bundle, locale: locale,
                        comment: "Pages the calendar forward"))
    }
  }

  private func step(_ months: Int, symbol: String, help: String) -> some View {
    Button {
      if let moved = calendar.date(byAdding: .month, value: months, to: visibleMonth) {
        visibleMonth = moved
      }
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.textSecondary)
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private var weekdays: some View {
    // Standalone symbols, which is the form a heading takes: some
    // languages inflect a weekday differently inside a sentence.
    let symbols = calendar.veryShortStandaloneWeekdaySymbols
    let ordered = (0 ..< 7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    return HStack(spacing: 0) {
      ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
        Text(verbatim: symbol)
          .font(Theme.Font.footnote)
          .fontWeight(.semibold)
          .foregroundStyle(Color.textMuted)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var grid: some View {
    VStack(spacing: 2) {
      ForEach(0 ..< 6, id: \.self) { week in
        HStack(spacing: 2) {
          ForEach(0 ..< 7, id: \.self) { weekday in
            if let day = days[week * 7 + weekday] {
              cell(day)
            }
          }
        }
      }
    }
  }

  /// Six weeks of days, starting on the row the first of the month falls
  /// in. Always six, so paging between a month that needs five rows and one
  /// that needs six does not make the popover jump.
  private var days: [Date?] {
    guard
      let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month],
                                                                     from: visibleMonth)),
      let week = calendar.dateInterval(of: .weekOfMonth, for: firstOfMonth)
    else { return Array(repeating: nil, count: 42) }
    return (0 ..< 42).map { calendar.date(byAdding: .day, value: $0, to: week.start) }
  }

  private func cell(_ day: Date) -> some View {
    let isChosen = calendar.isDate(day, inSameDayAs: date)
    let isToday = calendar.isDate(day, inSameDayAs: today)
    let isThisMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
    return Button {
      date = day
      isPresented = false
    } label: {
      Text(verbatim: "\(calendar.component(.day, from: day))")
        .font(Theme.Font.label)
        .monospacedDigit()
        .fontWeight(isChosen || isToday ? .semibold : .regular)
        .foregroundStyle(colour(chosen: isChosen, today: isToday, thisMonth: isThisMonth))
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background(
          isChosen ? Color.brand : .clear,
          in: RoundedRectangle(cornerRadius: Theme.Radius.control)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// White on the chosen day, the accent on today, and faded on the days
  /// either side of the month - which are shown rather than blanked so the
  /// weeks stay whole.
  private func colour(chosen: Bool, today: Bool, thisMonth: Bool) -> Color {
    if chosen {
      return .white
    }
    if today {
      return .brand
    }
    return thisMonth ? .textPrimary : .textFaint
  }
}
