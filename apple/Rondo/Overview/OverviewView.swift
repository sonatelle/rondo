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
          LevelledCard(summaries: model.summaries)
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
  let text: LocalizedStringKey
  var tint: Color = .textSecondary

  var body: some View {
    Text(text)
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
        CardTitle(text: "Next charge", tint: .urgentForeground)
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
          Text("Nothing scheduled")
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
        Text(next.subscription.name)
          .font(.system(size: 16, weight: .semibold))
          .lineLimit(1)
        Text(Formatting.chargeSummary(next, reference: model.referenceDay))
          .font(Theme.Font.body)
          .foregroundStyle(Color.textMuted)
          .lineLimit(1)
      }
    }
  }

  private func amount(_ next: Renewal) -> some View {
    Text(Formatting.amount(next.subscription.amount, currency: next.subscription.currency))
      .font(Theme.Font.statFigure)
      .monospacedDigit()
      // An amount never wraps. Broken across lines it stops being a
      // number: "₹700.00" came back as "₹70 / 0.0 / 0".
      .lineLimit(1)
  }
}

/// What it comes to a month, with every cycle spread evenly.
private struct LevelledCard: View {
  let summaries: [SpendingSummary]

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: Theme.Space.l) {
        CardTitle(text: "Monthly, levelled")
        Amounts(pairs: summaries.map { ($0.currency, $0.monthly) })
        Text("Currencies are never converted")
          .font(Theme.Font.footnote)
          .foregroundStyle(Color.textFaint)
      }
    }
  }
}

/// What actually falls due in the next thirty days.
private struct NextThirtyDaysCard: View {
  let totals: [WindowTotal]

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: Theme.Space.l) {
        CardTitle(text: "Next 30 days")
        Amounts(pairs: totals.map { ($0.currency, $0.total) })
        Text("\(totals.reduce(0) { $0 + Int($1.chargeCount) }) charges")
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
        Text("Coming up")
          .font(Theme.Font.sectionTitle)
        Text("by date")
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textFaint)
        Spacer()
        if model.upcoming.count > limit {
          Button("See all") { model.navigation = .subscriptions }
            .buttonStyle(.link)
            .font(Theme.Font.caption)
        }
      }
      .padding(.horizontal, Theme.Space.section)
      .padding(.top, Theme.Space.xxl)
      .padding(.bottom, Theme.Space.xl)

      if shown.isEmpty {
        Text("Nothing is scheduled yet.")
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
      Text(
        Formatting.amount(
          renewal.subscription.amount,
          currency: renewal.subscription.currency
        )
      )
      .font(Theme.Font.rowTitle)
      .monospacedDigit()
      .lineLimit(1)
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
        Text("Spent most on")
          .font(Theme.Font.sectionTitle)
        Text("since the first charge")
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textFaint)
      }
      .padding(.horizontal, 2)

      HStack(spacing: Theme.Space.xxl) {
        ForEach(Array(model.topSpending.prefix(limit)), id: \.subscription.id) { entry in
          TopSpendingCard(subscription: entry.subscription, total: entry.total)
        }
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct TopSpendingCard: View {
  let subscription: Subscription
  let total: SubscriptionTotal

  var body: some View {
    HStack(spacing: Theme.Space.xl) {
      ServiceMark(name: subscription.name, side: 32)
      VStack(alignment: .leading, spacing: 0) {
        Text(subscription.name)
          .font(Theme.Font.body)
          .lineLimit(1)
        Text("\(Int(total.chargeCount)) charges")
          .font(Theme.Font.footnote)
          .foregroundStyle(Color.textMuted)
      }
      Spacer(minLength: Theme.Space.s)
      Text(Formatting.amount(total.total, currency: total.currency))
        .font(Theme.Font.rowTitle)
        .monospacedDigit()
        .lineLimit(1)
    }
    .padding(.horizontal, Theme.Space.card)
    .padding(.vertical, Theme.Space.xxl)
    .frame(maxWidth: .infinity)
    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.mediumCard))
  }
}

/// How soon a charge falls, coloured by how soon that is.
///
/// Urgency is the only thing on this page that earns a colour; everything
/// else is neutral, so that red means one thing and always the same thing.
private struct UrgencyBadge: View {
  let date: CivilDate
  let reference: CivilDate

  var body: some View {
    let urgency = Urgency.of(date, from: reference)
    Text(Formatting.relative(date, from: reference))
      .font(Theme.Font.caption)
      .fontWeight(urgency == .distant ? .regular : .semibold)
      .foregroundStyle(foreground(urgency))
      // The same padding whatever the urgency, so only the fill changes.
      // Giving the pill its padding and the plain text none pushed the
      // words in a badged row nine points left of the words above it, and
      // a column of dates that does not line up reads as a mistake even
      // when every date in it is right.
      .padding(.horizontal, 9)
      .padding(.vertical, 2)
      .background(background(urgency), in: Capsule())
  }

  /// A distant charge gets no pill at all - a page where everything is
  /// badged has nothing left to draw the eye with.
  private func background(_ urgency: Urgency) -> Color {
    switch urgency {
    case .urgent: .urgentBackground
    case .soon: .warnBackground
    case .distant: .clear
    }
  }

  private func foreground(_ urgency: Urgency) -> Color {
    switch urgency {
    case .urgent: .urgentForeground
    case .soon: .warnForeground
    case .distant: .textMuted
    }
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
