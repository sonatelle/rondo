import SwiftUI

/// Twelve months at once, to answer one question: which of them turn out
/// expensive.
///
/// Not a smaller month view. A yearly plan lands its whole price in one
/// month and nothing in the other eleven, and that is invisible from
/// inside any single month - so this shows the totals and marks *which
/// days* carry a charge without ever saying how much a day cost. Precise
/// amounts per day would be noise here; the month view is one click away
/// for them.
struct YearGrid: View {
  let model: SubscriptionsModel

  /// Four across and three down, as the design lays them out.
  private static let columns = 4

  var body: some View {
    let priciest = priciestMonth
    VStack(spacing: Theme.Space.xl) {
      ForEach(rows, id: \.first?.id) { row in
        HStack(spacing: Theme.Space.xl) {
          ForEach(row) { month in
            MonthCard(
              month: month,
              charges: charges[monthKey(of: month.start)] ?? [],
              subscriptions: subscriptions,
              today: model.referenceDay,
              isPriciest: month.id == priciest
            ) {
              model.showCalendarMonth(containing: month.start)
            }
          }
        }
        .frame(maxHeight: .infinity)
      }
    }
    .padding(.horizontal, Theme.Space.section)
    .padding(.top, Theme.Space.card)
    .padding(.bottom, Theme.Space.section)
  }

  private var rows: [[SubscriptionsModel.CalendarMonth]] {
    stride(from: 0, to: model.calendarMonths.count, by: Self.columns).map { start in
      Array(model.calendarMonths[start ..< min(start + Self.columns, model.calendarMonths.count)])
    }
  }

  /// The charges of the year filed under the month each falls in.
  private var charges: [String: [DatedCharge]] {
    Dictionary(grouping: model.calendarCharges) { monthKey(of: $0.date) }
  }

  /// A civil date's year and month, which is what files a charge under a
  /// card. Taken off the front of the text rather than through `Calendar`:
  /// these are ISO dates and the first seven characters are exactly that.
  private func monthKey(of day: CivilDate) -> String {
    String(day.prefix(7))
  }

  private var subscriptions: [Uuid: Subscription] {
    Dictionary(
      model.allRenewals.map { ($0.subscription.id, $0.subscription) },
      uniquingKeysWith: { first, _ in first }
    )
  }

  /// The month with the largest converted total, or nothing when no two
  /// months differ - one of twelve equal months is not "the priciest", and
  /// colouring one of them would invent a fact.
  private var priciestMonth: CivilDate? {
    let totals = model.calendarMonths.compactMap { month -> (CivilDate, Decimal)? in
      guard month.total.convertedChargeCount > 0,
            let value = Formatting.decimal(month.total.total)
      else { return nil }
      return (month.start, value)
    }
    guard let highest = totals.max(by: { $0.1 < $1.1 }) else { return nil }
    guard totals.contains(where: { $0.1 < highest.1 }) else { return nil }
    return highest.0
  }
}

/// One month of the year, as a card.
private struct MonthCard: View {
  let month: SubscriptionsModel.CalendarMonth
  let charges: [DatedCharge]
  let subscriptions: [Uuid: Subscription]
  let today: CivilDate
  let isPriciest: Bool
  let open: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: open) {
      VStack(alignment: .leading, spacing: 2) {
        header
        subtitle
        Spacer(minLength: Theme.Space.m)
        DayStrip(charges: charges, subscriptions: subscriptions)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.horizontal, 15)
      .padding(.vertical, 13)
      .background(
        Color.surfaceRaised,
        in: RoundedRectangle(cornerRadius: Theme.Radius.mediumCard, style: .continuous)
      )
      .cardShadow()
      .overlay {
        if isThisMonth {
          RoundedRectangle(cornerRadius: Theme.Radius.mediumCard, style: .continuous)
            .strokeBorder(Color.brand, lineWidth: 2)
        }
      }
      // Months already behind us are dimmed rather than hidden: the year
      // is the unit here, and a half-empty grid would answer a different
      // question than the one this view is for.
      .opacity(isPast ? 0.62 : 1)
      .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.mediumCard, style: .continuous))
      .overlay {
        if isHovering {
          RoundedRectangle(cornerRadius: Theme.Radius.mediumCard, style: .continuous)
            .fill(Color.hoverBackground)
            .allowsHitTesting(false)
        }
      }
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(String(localized: "Show this month", bundle: Localization.bundle,
                 locale: Localization.locale,
                 comment: "Clicking a month card in the year view"))
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
      Text(verbatim: name)
        .font(Theme.Font.sectionTitle)
        .foregroundStyle(Color.textPrimary)
        .lineLimit(1)
      if isThisMonth {
        Text(verbatim: String(localized: "This month", bundle: Localization.bundle,
                              locale: Localization.locale,
                              comment: "Marks the current month in the year view"))
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(Color.brand)
          .lineLimit(1)
      }
      Spacer(minLength: Theme.Space.xs)
      Text(verbatim: totalText)
        .font(Theme.Font.sectionTitle)
        .monospacedDigit()
        // The one place amber is spent on something that is not urgent.
        // `warnForeground` is the same value the design gives it, so the
        // two share a token rather than keeping two copies in step.
        .foregroundStyle(isPriciest ? Color.warnForeground : Color.textPrimary)
        .lineLimit(1)
    }
  }

  private var subtitle: some View {
    Text(verbatim: subtitleText)
      .font(Theme.Font.groupTitle)
      .fontWeight(isPriciest ? .medium : .regular)
      .foregroundStyle(subtitleColour)
      .lineLimit(1)
      .truncationMode(.tail)
  }

  private var name: String {
    guard let date = Formatting.parseCivilDate(month.start) else { return month.start }
    return date.formatted(.dateTime.month(.abbreviated).locale(Localization.locale))
  }

  /// A dash rather than a zero when nothing converted: a month whose
  /// charges have no rate has not cost nothing.
  private var totalText: String {
    guard month.total.convertedChargeCount > 0 else { return "—" }
    return Formatting.amount(month.total.total, currency: month.total.currency)
  }

  /// How many charges, and the one thing worth saying about them.
  ///
  /// A yearly plan is what this whole view exists to surface, so it wins
  /// the line when there is one; otherwise the line says how far through
  /// the month the charges are.
  private var subtitleText: String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    let count = String(localized: "\(charges.count) charges", bundle: bundle, locale: locale,
                       comment: "How many charges make up a total")
    guard let detail = detailText else { return count }
    return "\(count) · \(detail)"
  }

  private var detailText: String? {
    let bundle = Localization.bundle
    let locale = Localization.locale
    let yearly = charges.compactMap { charge -> String? in
      guard let sub = subscriptions[charge.subscriptionId], sub.cycleUnit == .year else {
        return nil
      }
      return sub.name
    }
    if yearly.count == 1, let name = yearly.first {
      // Named, because "one of these months has a yearly plan in it" is
      // not actionable and "it is Netflix" is.
      return String(localized: "includes yearly \(name)", bundle: bundle, locale: locale,
                    comment: "Year view: this month carries a yearly plan, and which")
    }
    if yearly.count > 1 {
      return String(localized: "\(yearly.count) yearly plans", bundle: bundle, locale: locale,
                    comment: "Year view: this month carries more than one yearly plan")
    }
    guard !charges.isEmpty else { return nil }
    let past = charges.filter { $0.date < today }.count
    if past == charges.count {
      return String(localized: "already charged", bundle: bundle, locale: locale,
                    comment: "Year view: every charge in this month has happened")
    }
    if past > 0 {
      return String(localized: "\(past) already charged", bundle: bundle, locale: locale,
                    comment: "Year view: some of this month's charges have happened")
    }
    return nil
  }

  private var subtitleColour: Color {
    if isPriciest {
      return .warnForeground
    }
    return isPast ? .textFaint : .textMuted
  }

  private var isThisMonth: Bool {
    month.start.prefix(7) == today.prefix(7)
  }

  private var isPast: Bool {
    month.start.prefix(7) < today.prefix(7)
  }
}

/// Thirty-one cells, filled on the days something falls due.
///
/// Whether, never how much. A yearly plan is marked in the accent so the
/// month it lands in can be picked out of twelve at a glance; everything
/// else is the pale mark.
private struct DayStrip: View {
  let charges: [DatedCharge]
  let subscriptions: [Uuid: Subscription]

  var body: some View {
    HStack(spacing: 1) {
      ForEach(1 ... 31, id: \.self) { day in
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .fill(colour(of: day))
          .frame(maxWidth: .infinity)
      }
    }
    .frame(height: 5)
  }

  private func colour(of day: Int) -> Color {
    let onThisDay = charges.filter { dayOfMonth(of: $0.date) == day }
    guard !onThisDay.isEmpty else { return .clear }
    let carriesYearly = onThisDay.contains { charge in
      subscriptions[charge.subscriptionId]?.cycleUnit == .year
    }
    return carriesYearly ? .brand : .chargeMark
  }

  /// The day-of-month from an ISO date, which is its last two characters.
  private func dayOfMonth(of date: CivilDate) -> Int {
    Int(date.suffix(2)) ?? 0
  }
}

// MARK: - Previews

/// The populated model, already switched to the year. A preview of this
/// view against a model at month scale would draw twelve empty cards,
/// since the months are only asked for at year scale.
@MainActor
private func yearModel() -> SubscriptionsModel {
  let model = PreviewData.populated()
  model.setCalendarScale(.year)
  return model
}

#Preview("Calendar · year") {
  CalendarView(model: yearModel())
    .frame(width: 900, height: 740)
}

#Preview("Calendar · year at the window's floor") {
  CalendarView(model: yearModel())
    .frame(width: RondoWindow.minimumWidth - RondoWindow.minimumSidebarWidth,
           height: RondoWindow.minimumHeight)
}
