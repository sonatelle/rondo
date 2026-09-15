import SwiftUI

/// The full list gathered into cards, one per group.
///
/// The table answers "what am I paying for"; this answers "how much is on
/// that card", which the table cannot because the answer is spread down a
/// column. Each card carries its own figure, and the columns drop to the
/// three that identify a row and price it - the rest is what the table is
/// for.
struct GroupedList: View {
  let model: SubscriptionsModel
  /// What a row does when it is double-clicked, as in the table.
  let open: (Renewal) -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.Space.xxl) {
        ForEach(model.groups) { group in
          GroupCard(group: group, today: model.referenceDay, model: model, open: open)
        }
      }
      .padding(.horizontal, Theme.Space.section)
      .padding(.top, Theme.Space.xxl)
      .padding(.bottom, Theme.Space.card + 2)
    }
  }
}

/// One group, with what it comes to a month.
private struct GroupCard: View {
  let group: SubscriptionsModel.Group
  let today: CivilDate
  let model: SubscriptionsModel
  let open: (Renewal) -> Void

  var body: some View {
    VStack(spacing: 0) {
      header
      ForEach(group.renewals) { renewal in
        GroupRow(
          renewal: renewal,
          today: today,
          converted: model.convertedPrices[renewal.subscription.id],
          primaryCurrency: model.primaryCurrency
        ) {
          open(renewal)
        }
      }
    }
    .background(
      Color.surfaceRaised,
      in: RoundedRectangle(cornerRadius: Theme.Radius.mediumCard, style: .continuous)
    )
    .cardShadow()
  }

  private var header: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return HStack(spacing: Theme.Space.xl) {
      Text(verbatim: group.title)
        .font(Theme.Font.sectionTitle)
        .foregroundStyle(Color.textPrimary)
        .lineLimit(1)
        .truncationMode(.tail)
      Text(verbatim: String(localized: "\(group.renewals.count) active",
                            bundle: bundle, locale: locale,
                            comment: "Beside the title: how many subscriptions are being paid for"))
        .font(Theme.Font.caption)
        .foregroundStyle(Color.textFaint)
        .lineLimit(1)
      Spacer(minLength: Theme.Space.m)
      HStack(spacing: Theme.Space.s) {
        Text(verbatim: String(localized: "Levelled monthly", bundle: bundle, locale: locale,
                              comment: "Label on the total beside the filters"))
          .font(Theme.Font.label)
          .foregroundStyle(Color.textSecondary)
        Text(verbatim: totalText)
          .font(Theme.Font.label)
          .fontWeight(.semibold)
          .monospacedDigit()
          .foregroundStyle(Color.textPrimary)
      }
      .lineLimit(1)
    }
    .padding(.horizontal, Theme.Space.section - 2)
    .padding(.vertical, Theme.Space.xl)
  }

  /// A dash rather than a zero where nothing in the group converted: the
  /// group costs something, and what it costs is unknown.
  private var totalText: String {
    guard let total = group.total, total.subscriptionCount > 0 else { return "—" }
    return Formatting.amount(total.monthly, currency: total.currency)
  }
}

/// One subscription inside a group.
///
/// Three columns rather than the table's seven: what it is, what it costs,
/// and how soon. Which card pays for it is the card it is on, and the rest
/// is a question for the table.
private struct GroupRow: View {
  let renewal: Renewal
  let today: CivilDate
  let converted: DecimalString?
  let primaryCurrency: String
  let open: () -> Void

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: Theme.Space.xxl) {
      Text(verbatim: renewal.subscription.name)
        .font(Theme.Font.body)
        .foregroundStyle(Color.textPrimary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
      TwoLineAmount(
        written: Formatting.amount(
          renewal.subscription.amount,
          currency: renewal.subscription.currency,
          convertedTo: primaryCurrency,
          converted: converted
        ),
        font: Theme.Font.body
      )
      .frame(width: 92, alignment: .trailing)
      UrgencyBadge(date: renewal.date, reference: today)
        .frame(width: 104, alignment: .trailing)
    }
    .padding(.horizontal, Theme.Space.section - 2)
    .padding(.vertical, Theme.Space.l - 1)
    .background(isHovering ? Color.hoverBackground : .clear)
    .overlay(alignment: .top) {
      Rectangle().fill(Color.separatorLine).frame(height: 0.5)
    }
    .contentShape(Rectangle())
    .onHover { isHovering = $0 }
    .onTapGesture(count: 2, perform: open)
  }
}

/// Which way the list is arranged.
///
/// A menu rather than a segmented control, for the reason the analytics
/// range is one: these are phrases, and segments holding phrases stretch
/// the toolbar out of shape.
struct GroupingPicker: View {
  let model: SubscriptionsModel

  @State private var isHovering = false

  var body: some View {
    Menu {
      ForEach(Grouping.allCases) { grouping in
        Button {
          model.setGrouping(grouping)
        } label: {
          if model.grouping == grouping {
            Label(grouping.title, systemImage: "checkmark")
          } else {
            Text(verbatim: grouping.title)
          }
        }
      }
    } label: {
      HStack(spacing: Theme.Space.s) {
        Text(verbatim: model.grouping.title)
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textSecondary)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Color.textFaint)
      }
      .padding(.horizontal, Theme.Space.l)
      .frame(height: 26)
      .background(
        isHovering ? Color.hoverBackground : Color.fieldBackground,
        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { isHovering = $0 }
  }
}

// MARK: - Previews

@MainActor
private func groupedModel() -> SubscriptionsModel {
  let model = PreviewData.populated()
  model.setGrouping(.paymentMethod)
  return model
}

#Preview("Grouped · wide") {
  GroupedList(model: groupedModel(), open: { _ in })
    .frame(width: 860, height: 620)
    .background(Color.surface)
}

#Preview("Grouped · at the window's floor") {
  GroupedList(model: groupedModel(), open: { _ in })
    .frame(width: RondoWindow.minimumWidth - RondoWindow.minimumSidebarWidth,
           height: RondoWindow.minimumHeight)
    .background(Color.surface)
}
