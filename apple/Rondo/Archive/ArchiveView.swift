import SwiftUI

/// What was stopped, with the record kept.
///
/// Cards rather than the table the other list pages use, because the
/// questions are different ones. A list of what you pay for is read by
/// column - price, cycle, next charge. This is read a row at a time: what
/// it was, how long it ran, what it came to. Nothing here has a next
/// charge to sort by.
struct ArchiveView: View {
  let model: SubscriptionsModel

  /// Every archived subscription, newest stop first.
  ///
  /// Ones whose day was never recorded sort last rather than first: an
  /// unknown day is not a very old one, and putting them at the top would
  /// say they were.
  private var archived: [Renewal] {
    model.renewals.sorted { left, right in
      switch (left.subscription.archivedOn, right.subscription.archivedOn) {
      case let (lhs?, rhs?): lhs > rhs
      case (nil, _): false
      case (_, nil): true
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      if archived.isEmpty {
        // The same words the table page used to show here. A page that
        // simply goes blank reads as something that failed to load.
        ContentUnavailableView {
          Label {
            Text(verbatim: String(localized: "Nothing archived", bundle: Localization.bundle,
                                  locale: Localization.locale,
                                  comment: "Empty state: nothing has been archived"))
          } icon: {
            Image(systemName: "archivebox")
          }
        } description: {
          Text(verbatim: String(
            localized: "Archiving keeps a subscription's record but stops counting it.",
            bundle: Localization.bundle, locale: Localization.locale,
            comment: "Under the empty archive"
          ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ArchiveSummaryStrip(totals: model.archiveTotals)
        ScrollView {
          VStack(spacing: Theme.Space.xl) {
            ForEach(archived) { renewal in
              ArchiveCard(
                subscription: renewal.subscription,
                spent: model.convertedTotals[renewal.subscription.id],
                billed: model.totals[renewal.subscription.id],
                primaryCurrency: model.primaryCurrency,
                monthly: model.monthlyEquivalent(
                  amount: renewal.subscription.amount,
                  currency: renewal.subscription.currency,
                  cycleCount: renewal.subscription.cycleCount,
                  cycleUnit: renewal.subscription.cycleUnit
                )
              ) {
                model.setArchived(renewal.subscription, false)
              }
            }
          }
          .padding(.horizontal, Theme.Space.section)
          .padding(.vertical, Theme.Space.xxl)
        }
      }
    }
    // Filled rather than sized to its contents: an empty page would
    // otherwise leave the window's own background showing beside it.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.surface)
  }
}

/// What the stopped subscriptions came to, and what stopping them saves.
private struct ArchiveSummaryStrip: View {
  let totals: ArchiveTotals?

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    HStack(alignment: .top, spacing: 26) {
      figure(
        String(localized: "These cost altogether", bundle: bundle, locale: locale,
               comment: "Archive strip: what the stopped subscriptions came to"),
        spentText,
        tint: .textPrimary
      )

      figure(
        String(localized: "Saved a month", bundle: bundle, locale: locale,
               comment: "Archive strip: what stopping them saves every month"),
        savedText,
        // The one figure in Rondo drawn in green, and it earns it: this
        // is the only number on any screen that is good news. Red and
        // amber mean "charged soon" everywhere else, and green means
        // nothing at all - which is why it is free to mean this.
        tint: .success
      )
      .padding(.leading, 26)
      .overlay(alignment: .leading) {
        Rectangle().fill(Color.separatorLine).frame(width: 0.5)
      }

      if let missing = totals?.unconvertedCurrencies, !missing.isEmpty {
        Text(verbatim: String(localized: "no rate for \(missing.joined(separator: ", "))",
                              bundle: bundle, locale: locale,
                              comment: "Under a window total, naming what it leaves out"))
          .font(Theme.Font.footnote)
          .foregroundStyle(Color.danger)
      }

      Spacer(minLength: Theme.Space.card)
    }
    .padding(.horizontal, Theme.Space.section)
    .padding(.vertical, Theme.Space.xxl)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color.separatorLine).frame(height: 0.5)
    }
  }

  private func figure(_ title: String, _ value: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: title)
        .font(Theme.Font.groupTitle)
        .foregroundStyle(Color.textMuted)
        .lineLimit(1)
      Text(verbatim: value)
        .font(.system(size: 19, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(tint)
        .lineLimit(1)
    }
  }

  /// A dash rather than a zero where nothing converted: these cost
  /// something, and what they cost is unknown rather than nil.
  private var spentText: String {
    guard let totals, totals.convertedCount > 0 else { return "—" }
    return Formatting.amount(totals.spent, currency: totals.currency)
  }

  private var savedText: String {
    guard let totals, totals.convertedCount > 0 else { return "—" }
    return Formatting.amount(totals.monthlySaved, currency: totals.currency)
  }
}

/// One stopped subscription.
private struct ArchiveCard: View {
  let subscription: Subscription
  let spent: DecimalString?
  let billed: SubscriptionTotal?
  let primaryCurrency: String
  let monthly: DecimalString?
  let restore: () -> Void

  var body: some View {
    HStack(spacing: Theme.Space.xxl) {
      // Drained of colour, which is what marks the whole page: these are
      // kept rather than current, and a row as bright as a live one would
      // read as one.
      ServiceMark(name: subscription.name)
        .grayscale(1)
        .opacity(0.75)

      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: subscription.name)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(Color.textSecondary)
          .lineLimit(1)
          .truncationMode(.tail)
        if let summary = Formatting.archiveSummary(subscription) {
          Text(verbatim: summary)
            .font(Theme.Font.caption)
            .foregroundStyle(Color.textFaint)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .trailing, spacing: 1) {
        Text(verbatim: spentText)
          .font(.system(size: 15))
          .monospacedDigit()
          .foregroundStyle(Color.textSecondary)
          .lineLimit(1)
        Text(verbatim: footnote)
          .font(Theme.Font.footnote)
          .foregroundStyle(Color.textFaint)
          .lineLimit(1)
      }

      RestoreButton(action: restore)
    }
    .padding(.horizontal, Theme.Space.section - 2)
    .padding(.vertical, Theme.Space.xxl)
    .background(
      Color.surfaceRaised,
      in: RoundedRectangle(cornerRadius: Theme.Radius.mediumCard, style: .continuous)
    )
    .cardShadow()
  }

  /// What it cost altogether, converted where a rate reaches it and in
  /// what it was billed where none does.
  private var spentText: String {
    guard let billed else { return "—" }
    return Formatting.amount(
      billed.total,
      currency: billed.currency,
      convertedTo: primaryCurrency,
      converted: spent
    ).primary
  }

  /// The billed total under the converted one, and what it cost a month
  /// while it ran - which is this card's share of "saved a month" above.
  private var footnote: String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    let permonth = monthly.map {
      String(localized: "\(Formatting.amount($0, currency: subscription.currency)) a month",
             bundle: bundle, locale: locale,
             comment: "Archive card: what it cost each month while it ran")
    }
    let amounts = Formatting.amount(
      billed?.total ?? subscription.amount,
      currency: billed?.currency ?? subscription.currency,
      convertedTo: primaryCurrency,
      converted: spent
    )
    return [amounts.secondary, permonth].compactMap(\.self).joined(separator: " · ")
  }
}

/// Puts one back where it was.
private struct RestoreButton: View {
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Text(verbatim: String(localized: "Restore", bundle: Localization.bundle,
                            locale: Localization.locale,
                            comment: "Puts an archived subscription back among the active ones"))
        .font(Theme.Font.caption)
        .foregroundStyle(Color.textPrimary)
        .lineLimit(1)
        .padding(.horizontal, Theme.Space.xl)
        .frame(height: 26)
        .background(
          isHovering ? Color.hoverBackground : Color.fieldBackground,
          in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }
}

// MARK: - Previews

@MainActor
private func archiveModel() -> SubscriptionsModel {
  let model = PreviewData.populated()
  model.navigation = .archived
  return model
}

#Preview("Archive · wide") {
  ArchiveView(model: archiveModel())
    .frame(width: 820, height: 560)
}

#Preview("Archive · at the window's floor") {
  ArchiveView(model: archiveModel())
    .frame(width: RondoWindow.minimumWidth - RondoWindow.minimumSidebarWidth,
           height: RondoWindow.minimumHeight)
}

#Preview("Archive · nothing stopped yet") {
  ArchiveView(model: PreviewData.empty())
    .frame(width: 820, height: 360)
}
