import SwiftUI

/// The page the window opens on: what is charged next, what it all comes
/// to, and what has cost the most.
///
/// Three readings of the same data, because the questions people actually
/// ask are different ones. "When is the next charge" is answered by a date,
/// "what do I spend" by a levelled monthly figure, and "what will my card
/// be charged" by what falls due in the next thirty days - and a yearly
/// plan renewing next week makes those last two disagree, correctly.
struct OverviewView: View {
  let model: SubscriptionsModel

  /// How many charges the upcoming card lists before deferring to the full
  /// list. Four rows is what the design shows and about what fits without
  /// the card growing taller than the three above it.
  private static let upcomingShown = 4

  /// How many of the biggest spenders get a card of their own.
  private static let topSpendingShown = 3

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.Space.block) {
        HStack(alignment: .top, spacing: Theme.Space.xxl) {
          NextChargeCard(model: model)
          LevelledCard(summaries: model.summaries, converted: model.converted)
          NextThirtyDaysCard(totals: model.next30Days)
        }
        .fixedSize(horizontal: false, vertical: true)

        UpcomingCard(model: model, limit: Self.upcomingShown)

        if !model.topSpending.isEmpty {
          TopSpendingSection(model: model, limit: Self.topSpendingShown)
        }
      }
      .padding(.horizontal, Theme.Space.window)
      .padding(.vertical, Theme.Space.block)
    }
    .background(Color.surface)
  }
}

// MARK: - The three cards

/// The shape every card on this page shares.
private struct Card<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(.horizontal, Theme.Space.section)
      .padding(.vertical, Theme.Space.card + 2)
      // Equal width, full height. `layoutPriority` is not a way to say
      // "wider": giving one card a higher priority let it take the whole
      // row, and the two beside it were squeezed to a dozen points - narrow
      // enough that their footnote wrapped one character per line and grew
      // a thousand points tall.
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.largeCard))
  }
}

/// A card's small heading.
private struct CardTitle: View {
  /// Already through the catalogue; a key would follow the system's
  /// language rather than the chosen one.
  let text: String
  var tint: Color = .textSecondary

  var body: some View {
    Text(verbatim: text)
      .font(Theme.Font.cardTitle)
      .foregroundStyle(tint)
  }
}

/// What is charged next, and how soon.
///
/// Wider than its neighbours because it carries a name as well as a figure,
/// and because it is the one thing on the page somebody might act on.
private struct NextChargeCard: View {
  let model: SubscriptionsModel

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: Theme.Space.xxl) {
        CardTitle(text: String(localized: "Next charge", bundle: Localization.bundle,
                               locale: Localization.locale,
                               comment: "Overview card: the soonest charge"),
                  tint: .urgentForeground)
        if let next = model.upcoming.first {
          // Side by side while there is room, stacked when there is not.
          // This card carries five things where its neighbours carry two,
          // and at a third of a narrow window the row had nowhere to put
          // them: the amount broke across three lines and the date was cut
          // to "202…".
          ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.xxl) {
              identity(next)
              Spacer(minLength: Theme.Space.m)
              VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                amount(next)
                UrgencyBadge(date: next.date, reference: model.referenceDay)
              }
            }
            VStack(alignment: .leading, spacing: Theme.Space.l) {
              identity(next)
              HStack(spacing: Theme.Space.m) {
                amount(next)
                UrgencyBadge(date: next.date, reference: model.referenceDay)
              }
            }
          }
        } else {
          Text(verbatim: String(localized: "Nothing scheduled", bundle: Localization.bundle,
                                locale: Localization.locale,
                                comment: "Nothing is charged in the period being shown"))
            .font(Theme.Font.body)
            .foregroundStyle(Color.textMuted)
        }
      }
    }
  }

  /// The mark, the name, and when it falls due.
  private func identity(_ next: Renewal) -> some View {
    HStack(spacing: Theme.Space.xxl) {
      ServiceMark(name: next.subscription.name, side: 46)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: next.subscription.name)
          .font(.system(size: 16, weight: .semibold))
          .lineLimit(1)
        Text(verbatim: Formatting.chargeSummary(next, reference: model.referenceDay))
          .font(Theme.Font.body)
          .foregroundStyle(Color.textMuted)
          .lineLimit(1)
      }
    }
  }

  private func amount(_ next: Renewal) -> some View {
    TwoLineAmount(
      written: Formatting.amount(
        next.subscription.amount,
        currency: next.subscription.currency,
        convertedTo: Currencies.preferred,
        converted: model.convertedPrices[next.subscription.id]
      ),
      font: Theme.Font.statFigure
    )
  }
}

/// What it comes to a month, with every cycle spread evenly.
///
/// One figure in the primary currency where the rates allow it, and the
/// per-currency stack where they do not. The fallback is not a nicety: a
/// database with no rates converts nothing, and a headline of 0 there would
/// read as "you spend nothing" rather than "this could not be worked out".
private struct LevelledCard: View {
  let summaries: [SpendingSummary]
  let converted: ConvertedSpending?

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: Theme.Space.l) {
        CardTitle(text: String(localized: "Monthly, levelled", bundle: Localization.bundle,
                               locale: Localization.locale,
                               comment: "Overview card: every cycle spread over months"))
        if let converted, converted.subscriptionCount > 0 {
          Amounts(pairs: [(converted.currency, converted.monthly)])
          // Only the warning. Naming every rate that went into the figure
          // was tried here and ran to four lines of small print under a
          // card whose whole job is one number - the explanation was
          // longer than the thing explained. It lives on the filter bar's
          // tooltip instead, where it is asked for rather than displayed.
          //
          // What stays is the part that is not an explanation: a total
          // quietly missing three subscriptions looks exactly like a
          // smaller total, so that has to be on screen.
          if let missing = footnote(for: converted) {
            Text(verbatim: missing)
              .font(Theme.Font.footnote)
              .foregroundStyle(Color.danger)
          }
        } else {
          Amounts(pairs: summaries.map { ($0.currency, $0.monthly) })
          Text(verbatim: String(
            localized: "No rates yet, so each currency is counted apart",
            bundle: Localization.bundle, locale: Localization.locale,
            comment: "Under a total that could not be converted into one figure"
          ))
          .font(Theme.Font.footnote)
          .foregroundStyle(Color.textFaint)
        }
      }
    }
  }

  /// What the figure does *not* cover, or nothing when it covers everything.
  ///
  /// Deliberately not `Formatting.conversionNote`, which also names the
  /// rates: that belongs on hover, not under a card.
  private func footnote(for converted: ConvertedSpending) -> String? {
    guard !converted.unconverted.isEmpty else { return nil }
    let missing = converted.unconverted.reduce(0) { $0 + Int($1.subscriptionCount) }
    let codes = converted.unconverted.map(\.currency).joined(separator: ", ")
    return String(localized: "\(missing) not included: no rate for \(codes)",
                  bundle: Localization.bundle, locale: Localization.locale,
                  comment: "Under a total, naming the currencies it leaves out")
  }
}

/// What actually falls due in the next thirty days.
private struct NextThirtyDaysCard: View {
  let totals: [WindowTotal]

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: Theme.Space.l) {
        CardTitle(text: String(localized: "Next 30 days", bundle: Localization.bundle,
                               locale: Localization.locale,
                               comment: "Overview card: what actually falls due soon"))
        Amounts(pairs: totals.map { ($0.currency, $0.total) })
        Text(verbatim: String(localized: "\(totals.reduce(0) { $0 + Int($1.chargeCount) }) charges",
                              bundle: Localization.bundle, locale: Localization.locale,
                              comment: "How many charges make up a total"))
          .font(Theme.Font.footnote)
          .foregroundStyle(Color.textFaint)
      }
    }
  }
}

/// A stack of figures, one per currency, or a dash when there are none.
///
/// One line each rather than a joined sentence: currencies are never added
/// together, and stacking them says so without a word of explanation.
private struct Amounts: View {
  let pairs: [(currency: String, amount: DecimalString)]

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if pairs.isEmpty {
        Text(verbatim: "—")
          .font(Theme.Font.statFigure)
          .foregroundStyle(Color.textFaint)
      } else {
        ForEach(pairs, id: \.currency) { pair in
          Text(Formatting.amount(pair.amount, currency: pair.currency))
            .font(Theme.Font.statFigure)
            .monospacedDigit()
            .lineLimit(1)
        }
      }
    }
  }
}

// MARK: - What is coming

/// The next few charges, soonest first.
private struct UpcomingCard: View {
  let model: SubscriptionsModel
  let limit: Int

  private var shown: [Renewal] {
    Array(model.upcoming.prefix(limit))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
        Text(verbatim: String(localized: "Coming up", bundle: Localization.bundle,
                              locale: Localization.locale,
                              comment: "Overview section: the next few charges"))
          .font(Theme.Font.sectionTitle)
        Text(verbatim: String(localized: "by date", bundle: Localization.bundle,
                              locale: Localization.locale,
                              comment: "How the coming charges are ordered"))
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textFaint)
        Spacer()
        if model.upcoming.count > limit {
          Button(String(localized: "See all", bundle: Localization.bundle,
                        locale: Localization.locale,
                        comment: "Opens the full list from the overview"))
          {
            model.navigation = .subscriptions
          }
          .buttonStyle(.link)
          .font(Theme.Font.caption)
        }
      }
      .padding(.horizontal, Theme.Space.section)
      .padding(.top, Theme.Space.xxl)
      .padding(.bottom, Theme.Space.xl)

      if shown.isEmpty {
        Text(verbatim: String(localized: "Nothing is scheduled yet.",
                              bundle: Localization.bundle, locale: Localization.locale,
                              comment: "The overview has no charges to list"))
          .font(Theme.Font.body)
          .foregroundStyle(Color.textMuted)
          .padding(.horizontal, Theme.Space.section)
          .padding(.bottom, Theme.Space.section)
      } else {
        ForEach(shown, id: \.subscription.id) { renewal in
          Divider().foregroundStyle(Color.separatorLine)
          UpcomingRow(model: model, renewal: renewal)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.largeCard))
  }
}

private struct UpcomingRow: View {
  let model: SubscriptionsModel
  let renewal: Renewal

  var body: some View {
    HStack(spacing: Theme.Space.xxl) {
      ServiceMark(name: renewal.subscription.name, side: 34)
      VStack(alignment: .leading, spacing: 1) {
        Text(renewal.subscription.name)
          .font(Theme.Font.rowTitle)
          .lineLimit(1)
        Text(Formatting.cycleAndCategory(renewal, categories: model.categories))
          .font(Theme.Font.footnote)
          .foregroundStyle(Color.textMuted)
          .lineLimit(1)
      }
      Spacer(minLength: Theme.Space.m)
      TwoLineAmount(
        written: Formatting.amount(
          renewal.subscription.amount,
          currency: renewal.subscription.currency,
          convertedTo: Currencies.preferred,
          converted: model.convertedPrices[renewal.subscription.id]
        ),
        font: Theme.Font.rowTitle
      )
      UrgencyBadge(date: renewal.date, reference: model.referenceDay)
        .frame(width: 74, alignment: .trailing)
    }
    .padding(.horizontal, Theme.Space.section)
    .padding(.vertical, Theme.Space.xl - 1)
  }
}

// MARK: - What has cost the most

private struct TopSpendingSection: View {
  let model: SubscriptionsModel
  let limit: Int

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Space.xl) {
      HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
        Text(verbatim: String(localized: "Spent most on", bundle: Localization.bundle,
                              locale: Localization.locale,
                              comment: "Overview section: the costliest subscriptions"))
          .font(Theme.Font.sectionTitle)
        Text(verbatim: String(localized: "since the first charge", bundle: Localization.bundle,
                              locale: Localization.locale,
                              comment: "What period the ranking covers"))
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textFaint)
      }
      .padding(.horizontal, 2)

      HStack(spacing: Theme.Space.xxl) {
        ForEach(Array(model.topSpending.prefix(limit)), id: \.subscription.id) { entry in
          TopSpendingCard(
            subscription: entry.subscription,
            total: entry.total,
            converted: model.convertedTotals[entry.subscription.id]
          )
        }
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct TopSpendingCard: View {
  let subscription: Subscription
  let total: SubscriptionTotal
  /// The cumulative in the primary currency, when a rate reaches it.
  let converted: DecimalString?

  var body: some View {
    HStack(spacing: Theme.Space.xl) {
      ServiceMark(name: subscription.name, side: 32)
      VStack(alignment: .leading, spacing: 0) {
        Text(verbatim: subscription.name)
          .font(Theme.Font.body)
          .lineLimit(1)
        Text(verbatim: String(localized: "\(Int(total.chargeCount)) charges",
                              bundle: Localization.bundle, locale: Localization.locale,
                              comment: "How many charges make up a total"))
          .font(Theme.Font.footnote)
          .foregroundStyle(Color.textMuted)
      }
      Spacer(minLength: Theme.Space.s)
      // A cumulative, so it is converted at the rate of each charge's own
      // day rather than at today's - which is why it is asked for by id
      // rather than formatted from the subscription's current price.
      TwoLineAmount(
        written: Formatting.amount(
          total.total,
          currency: total.currency,
          convertedTo: Currencies.preferred,
          converted: converted
        ),
        font: Theme.Font.rowTitle
      )
    }
    .padding(.horizontal, Theme.Space.card)
    .padding(.vertical, Theme.Space.xxl)
    .frame(maxWidth: .infinity)
    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.mediumCard))
  }
}

// MARK: - Previews

// Pinned to the widths that matter rather than to one comfortable size.
// The narrow one is the window's own floor: whatever it shows is the worst
// this page is allowed to look, and if that is not good enough the floor is
// wrong rather than the layout.

#Preview("Overview · wide") {
  OverviewView(model: PreviewData.populated())
    .frame(width: 900, height: 700)
}

#Preview("Overview · at the window's floor") {
  OverviewView(model: PreviewData.populated())
    .frame(width: RondoWindow.minimumWidth - RondoWindow.minimumSidebarWidth, height: 520)
}

#Preview("Overview · nothing yet") {
  OverviewView(model: PreviewData.empty())
    .frame(width: 900, height: 400)
}
