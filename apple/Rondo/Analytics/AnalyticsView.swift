import SwiftUI

/// What the money went on, over time and by kind.
///
/// Four readings that answer different questions. The cards say what has
/// been spent and what it comes to a month; the chart says which months
/// were expensive and which are still a forecast; the bars say which
/// subscriptions the money went to; the split says what kind of thing they
/// are. Every figure on this page is the core's own - nothing here adds
/// money up.
struct AnalyticsView: View {
  let model: SubscriptionsModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.Space.card + 2) {
        StatCards(model: model)
        MonthlySpendingCard(model: model)
        HStack(alignment: .top, spacing: Theme.Space.xxl) {
          TopSpendingCard(model: model)
            .containerRelativeFrame(.horizontal, count: 5, span: 3, spacing: Theme.Space.xxl)
          CategorySplitCard(model: model)
        }
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, Theme.Space.block)
      .padding(.vertical, Theme.Space.section)
    }
    .background(Color.surface)
  }
}

/// The shape every card on this page shares.
private struct Card<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(.horizontal, Theme.Space.card + 2)
      .padding(.vertical, Theme.Space.card)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background(
        Color.surfaceRaised,
        in: RoundedRectangle(cornerRadius: Theme.Radius.mediumCard, style: .continuous)
      )
      .cardShadow()
  }
}

/// A card's small heading, and the aside beside it.
private struct CardHeading: View {
  let title: String
  var note: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
      Text(verbatim: title)
        .font(Theme.Font.sectionTitle)
        .foregroundStyle(Color.textPrimary)
      if let note {
        Text(verbatim: note)
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textFaint)
          .lineLimit(1)
      }
    }
  }
}

// MARK: - The four figures

/// What has been spent, what it comes to a month, and how many there are.
private struct StatCards: View {
  let model: SubscriptionsModel

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    HStack(alignment: .top, spacing: Theme.Space.xxl) {
      stat(
        String(localized: "Year to date", bundle: bundle, locale: locale,
               comment: "Analytics card: charged since 1 January"),
        window: model.yearToDate
      )
      stat(
        String(localized: "All time", bundle: bundle, locale: locale,
               comment: "Analytics card: charged since the first charge ever"),
        window: model.allTime
      )
      stat(
        String(localized: "Levelled monthly", bundle: bundle, locale: locale,
               comment: "Analytics card: what it all comes to in a month"),
        value: model.converted.map {
          Formatting.amount($0.monthly, currency: $0.currency)
        },
        note: nil
      )
      stat(
        String(localized: "Active", bundle: bundle, locale: locale,
               comment: "Analytics card: how many subscriptions are running"),
        value: "\(model.counts[.subscriptions] ?? 0)",
        note: String(localized: "\(model.counts[.archived] ?? 0) archived",
                     bundle: bundle, locale: locale,
                     comment: "Beside the title: how many subscriptions were stopped")
      )
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  /// A card built from one of the core's windows, which also knows what it
  /// had to leave out.
  private func stat(_ title: String, window: ConvertedWindow?) -> some View {
    let missing = window?.unconvertedCurrencies ?? []
    return stat(
      title,
      value: window.flatMap { window in
        window.convertedChargeCount > 0
          ? Formatting.amount(window.total, currency: window.currency)
          : nil
      },
      note: missing.isEmpty ? nil : String(
        localized: "no rate for \(missing.joined(separator: ", "))",
        bundle: Localization.bundle, locale: Localization.locale,
        comment: "Under a window total, naming what it leaves out"
      ),
      noteIsWarning: !missing.isEmpty
    )
  }

  private func stat(
    _ title: String,
    value: String?,
    note: String?,
    noteIsWarning: Bool = false
  ) -> some View {
    Card {
      VStack(alignment: .leading, spacing: 0) {
        Text(verbatim: title)
          .font(Theme.Font.cardTitle)
          .foregroundStyle(Color.textMuted)
          .lineLimit(1)
        // A dash rather than a zero when nothing converted: a total with
        // no rate behind it is unknown, not nothing.
        Text(verbatim: value ?? "—")
          .font(Theme.Font.analyticsFigure)
          .monospacedDigit()
          .foregroundStyle(Color.textPrimary)
          .lineLimit(1)
          .padding(.top, Theme.Space.s)
        Text(verbatim: note ?? " ")
          .font(Theme.Font.caption)
          .foregroundStyle(noteIsWarning ? Color.danger : Color.textFaint)
          .lineLimit(1)
          .padding(.top, 2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

// MARK: - The chart

/// A bar per month, and which of them have actually been billed.
private struct MonthlySpendingCard: View {
  let model: SubscriptionsModel

  /// How tall the bars are drawn. Fixed rather than proportional: the
  /// card sits between two others and a chart that grew with the window
  /// would push them about.
  private static let barHeight: CGFloat = 132

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    Card {
      VStack(alignment: .leading, spacing: 0) {
        CardHeading(
          title: String(localized: "Monthly spending", bundle: bundle, locale: locale,
                        comment: "Analytics chart: what was charged each month"),
          note: String(localized: "by the month each charge fell in",
                       bundle: bundle, locale: locale,
                       comment: "Under the chart title: charged, not levelled")
        )
        bars.padding(.top, Theme.Space.block)
        labels.padding(.top, Theme.Space.s)
        legend.padding(.top, Theme.Space.xl)
      }
    }
  }

  private var bars: some View {
    HStack(alignment: .bottom, spacing: Theme.Space.l) {
      ForEach(model.analyticsMonths) { month in
        Bar(
          month: month,
          fraction: fraction(of: month),
          kind: kind(of: month),
          height: Self.barHeight
        )
      }
    }
    .frame(height: Self.barHeight, alignment: .bottom)
  }

  private var labels: some View {
    HStack(spacing: Theme.Space.l) {
      ForEach(model.analyticsMonths) { month in
        Text(verbatim: name(of: month))
          .font(.system(size: 10.5, weight: kind(of: month) == .current ? .semibold : .regular))
          .foregroundStyle(kind(of: month) == .current ? Color.textPrimary : Color.textFaint)
          .lineLimit(1)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var legend: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(spacing: 0) {
      Rectangle().fill(Color.separatorLine).frame(height: 0.5)
      HStack(alignment: .top, spacing: Theme.Space.card) {
        swatch(.barCharged, String(localized: "Charged", bundle: bundle, locale: locale,
                                   comment: "Chart legend: months already billed"))
        swatch(.chargeMark, String(localized: "Forecast", bundle: bundle, locale: locale,
                                   comment: "Chart legend: months not billed yet"))
        Spacer(minLength: Theme.Space.card)
        if let note = anomaly {
          Text(verbatim: note)
            .font(Theme.Font.caption)
            .foregroundStyle(Color.textMuted)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.top, Theme.Space.l)
    }
  }

  private func swatch(_ colour: Color, _ title: String) -> some View {
    HStack(spacing: Theme.Space.s) {
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .fill(colour)
        .frame(width: 9, height: 9)
      Text(verbatim: title)
        .font(Theme.Font.caption)
        .foregroundStyle(Color.textMuted)
        .lineLimit(1)
    }
  }

  /// How tall a bar is, as a fraction of the tallest month on screen.
  ///
  /// Against the tallest rather than against a round number, because the
  /// question this chart answers is which months stand out from the
  /// others - and a scale chosen to make the differences small would hide
  /// exactly that.
  private func fraction(of month: SubscriptionsModel.MonthTotal) -> Double {
    guard let value = Formatting.decimal(month.total.total), tallest > 0 else { return 0 }
    return max(0, min(1, (value / tallest as NSDecimalNumber).doubleValue))
  }

  private var tallest: Decimal {
    model.analyticsMonths
      .compactMap { Formatting.decimal($0.total.total) }
      .max() ?? 0
  }

  private func kind(of month: SubscriptionsModel.MonthTotal) -> Bar.Kind {
    let thisMonth = model.referenceDay.prefix(7)
    if month.start.prefix(7) == thisMonth {
      return .current
    }
    return month.start.prefix(7) < thisMonth ? .charged : .forecast
  }

  private func name(of month: SubscriptionsModel.MonthTotal) -> String {
    guard let date = Formatting.parseCivilDate(month.start) else { return "" }
    return date.formatted(.dateTime.month(.abbreviated).locale(Localization.locale))
  }

  /// One sentence about the month that stands out, or nothing when none
  /// does.
  ///
  /// Only worth saying when a month is genuinely above the others and
  /// something explains it - a yearly plan landing in it. "March is the
  /// highest" on its own is visible from the chart and says nothing the
  /// bars have not.
  private var anomaly: String? {
    let dearest = model.analyticsMonths
      .compactMap { month -> (SubscriptionsModel.MonthTotal, Decimal)? in
        guard month.total.convertedChargeCount > 0,
              let value = Formatting.decimal(month.total.total)
        else { return nil }
        return (month, value)
      }
      .max { $0.1 < $1.1 }
    guard let dearest,
          model.analyticsMonths.contains(where: { month in
            (Formatting.decimal(month.total.total) ?? 0) < dearest.1
          })
    else { return nil }

    let yearly = model.calendarCharges.isEmpty ? [] : yearlyNames(in: dearest.0)
    guard !yearly.isEmpty else { return nil }
    return String(
      localized: "\(name(of: dearest.0)) is the highest: \(yearly.joined(separator: ", "))",
      bundle: Localization.bundle, locale: Localization.locale,
      comment: "Beside the chart: which month stands out and what is in it"
    )
  }

  /// Yearly plans billed in one month, by name.
  ///
  /// Read from the calendar's charges, which cover the span the calendar
  /// is on rather than the chart's - so this says nothing rather than
  /// guessing when the two do not overlap.
  private func yearlyNames(in month: SubscriptionsModel.MonthTotal) -> [String] {
    let subscriptions = Dictionary(
      model.allRenewals.map { ($0.subscription.id, $0.subscription) },
      uniquingKeysWith: { first, _ in first }
    )
    return model.calendarCharges
      .filter { $0.date.prefix(7) == month.start.prefix(7) }
      .compactMap { charge in
        guard let sub = subscriptions[charge.subscriptionId], sub.cycleUnit == .year else {
          return nil
        }
        return sub.name
      }
  }
}

/// One month's bar.
private struct Bar: View {
  enum Kind {
    case charged
    case current
    case forecast
  }

  let month: SubscriptionsModel.MonthTotal
  let fraction: Double
  let kind: Kind
  let height: CGFloat

  var body: some View {
    UnevenRoundedRectangle(
      topLeadingRadius: Theme.Space.s,
      topTrailingRadius: Theme.Space.s,
      style: .continuous
    )
    .fill(colour)
    .frame(maxWidth: .infinity)
    .frame(height: max(2, height * fraction))
    // Hung off the bar's own top edge rather than placed above it in a
    // stack: laid out as a sibling it sat at the top of the chart area
    // instead, which left a short month's figure floating in space with
    // nothing under it. An overlay takes no room in the layout, so a bar
    // at full height keeps its figure too.
    .overlay(alignment: .top) {
      if kind != .forecast, month.total.convertedChargeCount > 0 {
        Text(verbatim: Formatting.amount(month.total.total, currency: month.total.currency))
          .font(.system(size: 10, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(kind == .current ? Color.brand : Color.textMuted)
          .lineLimit(1)
          // Kept to the column's width so twelve of them across a narrow
          // window cannot overlap into an unreadable row.
          .minimumScaleFactor(0.6)
          // A fixed band and a plain offset rather than an alignment
          // guide: the guide was ignored here and left the figure sitting
          // inside the bar, where the current month's blue-on-blue was
          // invisible. Height 12 is the 10pt line, so -17 puts the band's
          // bottom edge five points clear of the bar's top.
          .frame(maxWidth: .infinity, minHeight: 12, maxHeight: 12)
          .offset(y: -17)
      }
    }
    .frame(maxHeight: .infinity, alignment: .bottom)
    .help(tooltip)
  }

  private var colour: Color {
    switch kind {
    case .charged: .barCharged
    case .current: .brand
    case .forecast: .chargeMark
    }
  }

  private var tooltip: String {
    guard month.total.convertedChargeCount > 0 else { return "" }
    return Formatting.amount(month.total.total, currency: month.total.currency)
  }
}

// MARK: - Where the money went

/// What each subscription has cost since its first charge.
private struct TopSpendingCard: View {
  let model: SubscriptionsModel

  /// How many rows the card lists. Enough to show where the money goes
  /// without the card growing past the one beside it.
  private static let shown = 6

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    Card {
      VStack(alignment: .leading, spacing: Theme.Space.xl) {
        CardHeading(
          title: String(localized: "Cost per subscription", bundle: bundle, locale: locale,
                        comment: "Analytics card: what each has cost in total"),
          note: String(localized: "since the first charge", bundle: bundle, locale: locale,
                       comment: "Under a cumulative total")
        )
        ForEach(Array(rows.enumerated()), id: \.element.subscription.id) { rank, row in
          SpendingRow(
            name: row.subscription.name,
            amount: row.amount,
            fraction: row.fraction,
            rank: rank
          )
        }
        if rows.isEmpty {
          Text(verbatim: String(localized: "Nothing has been charged yet.",
                                bundle: bundle, locale: locale,
                                comment: "The analytics page with no charges behind it"))
            .font(Theme.Font.caption)
            .foregroundStyle(Color.textFaint)
        }
      }
    }
  }

  /// The biggest spenders, with the converted figure where a rate reaches
  /// one and the billed total where none does.
  private var rows: [(subscription: Subscription, amount: String, fraction: Double)] {
    let ranked = model.topSpending.prefix(Self.shown)
    let largest = ranked.compactMap { value(of: $0) }.max() ?? 0
    return ranked.map { entry in
      let amount = model.convertedTotals[entry.subscription.id]
      return (
        subscription: entry.subscription,
        amount: Formatting.amount(
          amount ?? entry.total.total,
          currency: amount == nil ? entry.total.currency : model.primaryCurrency
        ),
        fraction: largest > 0
          ? max(0, min(1, ((value(of: entry) ?? 0) / largest as NSDecimalNumber).doubleValue))
          : 0
      )
    }
  }

  /// What a row is ranked and sized by: the converted figure when there is
  /// one, so the bars are comparable with each other.
  private func value(of entry: (subscription: Subscription, total: SubscriptionTotal))
    -> Decimal?
  {
    Formatting.decimal(model.convertedTotals[entry.subscription.id] ?? entry.total.total)
  }
}

/// One subscription's bar.
private struct SpendingRow: View {
  let name: String
  let amount: String
  let fraction: Double
  let rank: Int

  var body: some View {
    HStack(spacing: Theme.Space.xl) {
      Text(verbatim: name)
        .font(Theme.Font.label)
        .foregroundStyle(Color.textPrimary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(width: 96, alignment: .leading)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.hoverBackground)
          Capsule()
            .fill(Color.brand.opacity(weight))
            .frame(width: max(0, proxy.size.width * fraction))
        }
      }
      .frame(height: 9)
      Text(verbatim: amount)
        .font(Theme.Font.label)
        .monospacedDigit()
        .foregroundStyle(Color.textPrimary)
        .lineLimit(1)
        .frame(width: 84, alignment: .trailing)
    }
  }

  /// The blue fades down the ranking, which is what the design's ramp of
  /// five blues does. Drawn as one colour at falling opacity rather than
  /// as five tokens: the steps then hold in both appearances, and there is
  /// one value to change rather than five to keep in step.
  private var weight: Double {
    max(0.2, 1 - Double(rank) * 0.16)
  }
}

// MARK: - What kind of thing it is

/// Spending split by category, as one bar and a list.
private struct CategorySplitCard: View {
  let model: SubscriptionsModel

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    Card {
      VStack(alignment: .leading, spacing: Theme.Space.xxl) {
        CardHeading(title: String(localized: "By category", bundle: bundle, locale: locale,
                                  comment: "Analytics card: what kind of thing the money goes on"))
        if let split = model.analyticsShares, !split.shares.isEmpty {
          bar(split)
          rows(split)
          footnote(split)
        } else {
          Text(verbatim: String(localized: "Nothing to split yet.",
                                bundle: bundle, locale: locale,
                                comment: "The category card with no spending behind it"))
            .font(Theme.Font.caption)
            .foregroundStyle(Color.textFaint)
        }
      }
    }
  }

  private func bar(_ split: ConvertedShares) -> some View {
    GeometryReader { proxy in
      HStack(spacing: 0) {
        ForEach(split.shares, id: \.categoryId) { share in
          Rectangle()
            .fill(tint(of: share.categoryId))
            .frame(width: max(0, proxy.size.width * fraction(share, of: split)))
        }
      }
    }
    .frame(height: 11)
    .clipShape(Capsule())
  }

  private func rows(_ split: ConvertedShares) -> some View {
    VStack(spacing: Theme.Space.m) {
      ForEach(split.shares, id: \.categoryId) { share in
        HStack(spacing: Theme.Space.m) {
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(tint(of: share.categoryId))
            .frame(width: 9, height: 9)
          Text(verbatim: name(of: share.categoryId))
            .font(Theme.Font.label)
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
          Spacer(minLength: Theme.Space.m)
          Text(verbatim: Formatting.amount(share.monthly, currency: split.currency))
            .font(Theme.Font.label)
            .monospacedDigit()
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
          Text(verbatim: percentage(share, of: split))
            .font(Theme.Font.label)
            .monospacedDigit()
            .foregroundStyle(Color.textMuted)
            .lineLimit(1)
            .frame(width: 44, alignment: .trailing)
        }
      }
    }
  }

  private func footnote(_ split: ConvertedShares) -> some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(alignment: .leading, spacing: Theme.Space.s) {
      Rectangle().fill(Color.separatorLine).frame(height: 0.5)
      Text(verbatim: String(localized: "Levelled over a month, so a yearly plan counts as a twelfth.",
                            bundle: bundle, locale: locale,
                            comment: "Under the category split: how the figures are reckoned"))
        .font(Theme.Font.caption)
        .foregroundStyle(Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Theme.Space.s)
      if !split.unconvertedCurrencies.isEmpty {
        Text(verbatim: String(
          localized: "no rate for \(split.unconvertedCurrencies.joined(separator: ", "))",
          bundle: bundle, locale: locale,
          comment: "Under a window total, naming what it leaves out"
        ))
        .font(Theme.Font.caption)
        .foregroundStyle(Color.danger)
      }
    }
  }

  /// A share as a fraction of the total the core handed over.
  ///
  /// Of *that* total rather than of a sum taken here: the two would differ
  /// by nothing in practice and by everything in principle - one of them
  /// is the core's answer and the other is this view's guess at it.
  private func fraction(_ share: ConvertedShare, of split: ConvertedShares) -> Double {
    guard let value = Formatting.decimal(share.monthly),
          let total = Formatting.decimal(split.total), total > 0
    else { return 0 }
    return max(0, min(1, (value / total as NSDecimalNumber).doubleValue))
  }

  private func percentage(_ share: ConvertedShare, of split: ConvertedShares) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Localization.locale
    formatter.numberStyle = .percent
    formatter.maximumFractionDigits = 0
    return formatter.string(from: fraction(share, of: split) as NSNumber) ?? ""
  }

  private func category(_ id: Uuid?) -> Category? {
    guard let id else { return nil }
    return model.categories.first { $0.id == id }
  }

  private func tint(of id: Uuid?) -> Color {
    guard let category = category(id) else { return .textFaint }
    return Categories.tint(for: category.colorKey)
  }

  /// The category's name, or a word for the ones filed under nothing -
  /// which are kept in the split rather than dropped, so the slices add up
  /// to what is actually spent.
  private func name(of id: Uuid?) -> String {
    guard let category = category(id) else {
      return String(localized: "Uncategorized", bundle: Localization.bundle,
                    locale: Localization.locale,
                    comment: "The slice holding subscriptions filed under nothing")
    }
    return Categories.name(category.name, iconKey: category.iconKey)
  }
}

// MARK: - Previews

#Preview("Analytics · wide") {
  AnalyticsView(model: PreviewData.populated())
    .frame(width: 940, height: 740)
}

#Preview("Analytics · at the window's floor") {
  AnalyticsView(model: PreviewData.populated())
    .frame(width: RondoWindow.minimumWidth - RondoWindow.minimumSidebarWidth,
           height: RondoWindow.minimumHeight)
}

#Preview("Analytics · nothing yet") {
  AnalyticsView(model: PreviewData.empty())
    .frame(width: 940, height: 620)
}
