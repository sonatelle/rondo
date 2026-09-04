import SwiftUI

/// Every price a subscription has been charged at, newest first.
///
/// This is where what round 4 stored finally becomes something to read and
/// to add to. The line at the foot says why it is kept: charges are counted
/// at the price in force on their own day, so a total across a rise is the
/// real number rather than today's price multiplied out.
struct PriceHistoryCard: View {
  let model: SubscriptionsModel
  let subscription: Subscription

  @State private var isRecording = false

  var body: some View {
    VStack(spacing: 0) {
      let history = model.priceHistory(of: subscription.id)
      ForEach(Array(history.enumerated().reversed()), id: \.element.id) { index, price in
        row(price, previous: index > 0 ? history[index - 1] : nil, isCurrent: index == history.count - 1)
        FormDivider()
      }
      recordRow
    }
  }

  private func row(_ price: Price, previous: Price?, isCurrent: Bool) -> some View {
    HStack(spacing: Theme.Space.xl) {
      Text(Formatting.date(price.effectiveFrom))
        .font(Theme.Font.label)
        .monospacedDigit()
        .fontWeight(isCurrent ? .medium : .regular)
        .foregroundStyle(isCurrent ? Color.textPrimary : Color.textSecondary)
        .frame(width: FormRow<EmptyView>.labelWidth, alignment: .leading)
      Text(explanation(price, previous: previous, isCurrent: isCurrent))
        .font(Theme.Font.label)
        .foregroundStyle(Color.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(Formatting.amount(price.amount, currency: price.currency))
        .font(Theme.Font.label)
        .monospacedDigit()
        .foregroundStyle(isCurrent ? Color.textPrimary : Color.textSecondary)
        .lineLimit(1)
    }
    .padding(.horizontal, Theme.Space.card)
    .padding(.vertical, Theme.Space.l)
  }

  /// What a row says about itself: the current price and by how much it
  /// rose, or that this is where the subscription started.
  ///
  /// The difference is worked out from two amounts the core gave, which is
  /// arithmetic this side is allowed: subtracting two numbers already in
  /// the same currency answers a question about display, not about money.
  private func explanation(_ price: Price, previous: Price?, isCurrent: Bool) -> String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    guard isCurrent else {
      return previous == nil
        ? String(localized: "The price it started at", bundle: bundle, locale: locale,
                 comment: "Price history: the earliest entry")
        : String(localized: "Was charged at this", bundle: bundle, locale: locale,
                 comment: "Price history: a price that is no longer current")
    }
    guard let previous,
          let now = Formatting.decimal(price.amount),
          let before = Formatting.decimal(previous.amount),
          now != before
    else {
      return String(localized: "Current price", bundle: bundle, locale: locale,
                    comment: "Price history: the entry in force")
    }
    let change = Formatting.amount(
      "\(abs(now - before))",
      currency: price.currency
    )
    return now > before
      ? String(localized: "Current price · up \(change)", bundle: bundle, locale: locale,
               comment: "Price history: the current entry, and the rise that produced it")
      : String(localized: "Current price · down \(change)", bundle: bundle, locale: locale,
               comment: "Price history: the current entry, after a fall")
  }

  private var recordRow: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return HStack(spacing: Theme.Space.l) {
      Button {
        isRecording = true
      } label: {
        Label {
          Text(verbatim: String(localized: "Record a price change…", bundle: bundle,
                                locale: locale, comment: "Opens the sheet for a price rise"))
        } icon: {
          Image(systemName: "plus")
        }
        .font(Theme.Font.label)
      }
      .buttonStyle(.link)
      Spacer(minLength: Theme.Space.m)
      FormNote(text: String(localized: "Past charges keep the price they were charged at",
                            bundle: bundle, locale: locale,
                            comment: "Beside the button that records a price change"))
    }
    .padding(.horizontal, Theme.Space.card)
    .padding(.vertical, Theme.Space.l)
    .sheet(isPresented: $isRecording) {
      PriceChangeSheet(model: model, subscription: subscription)
    }
  }
}

/// Records that the price changed, and from when.
///
/// A change of price, not a correction of one. Editing the price on the
/// form above corrects the entry in force; this adds a new one and leaves
/// earlier charges at what they cost. Only the person knows which just
/// happened, so they are two different actions rather than one guess.
private struct PriceChangeSheet: View {
  let model: SubscriptionsModel
  let subscription: Subscription

  @Environment(\.dismiss) private var dismiss
  @State private var amount = ""
  @State private var effectiveFrom = Date()
  @State private var rejection: String?

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: String(localized: "Record a price change", bundle: bundle, locale: locale,
                              comment: "Title of the price change sheet"))
          .font(.system(size: 15, weight: .semibold))
        Text(verbatim: String(
          localized: "Charges before this day keep the price they were charged at.",
          bundle: bundle, locale: locale, comment: "Subtitle of the price change sheet"
        ))
        .font(Theme.Font.body)
        .foregroundStyle(Color.textMuted)
      }
      .padding(.horizontal, Theme.Space.block)
      .padding(.top, Theme.Space.section)
      .padding(.bottom, Theme.Space.xxl)

      FormCard {
        FormRow(label: String(localized: "New price", bundle: bundle, locale: locale,
                              comment: "Form row: the price from the new day on"),
                spacing: Theme.Space.l)
        {
          FormField(text: $amount, width: 96)
          Text(verbatim: subscription.currency)
            .font(Theme.Font.body)
            .foregroundStyle(Color.textSecondary)
          Spacer(minLength: 0)
        }
        FormDivider()
        FormRow(label: String(localized: "In force from", bundle: bundle, locale: locale,
                              comment: "Form row: the day the new price starts"))
        {
          DateField(date: $effectiveFrom)
          Spacer(minLength: 0)
        }
      }
      .padding(.horizontal, Theme.Space.xxl)

      if let rejection {
        Text(rejection)
          .font(Theme.Font.caption)
          .foregroundStyle(Color.danger)
          .padding(.horizontal, Theme.Space.block)
          .padding(.top, Theme.Space.xl)
      }

      HStack {
        Spacer()
        Button(String(localized: "Cancel", bundle: bundle, locale: locale,
                      comment: "Closes the sheet without saving"), role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(String(localized: "Record", bundle: bundle, locale: locale,
                      comment: "Saves the price change")) { record() }
          .keyboardShortcut(.defaultAction)
          .disabled(amount.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding(.horizontal, Theme.Space.block)
      .padding(.vertical, Theme.Space.card)
    }
    .frame(width: 440)
    .background(Color.surface)
  }

  private func record() {
    let accepted = model.recordPriceChange(
      of: subscription,
      amount: amount.trimmingCharacters(in: .whitespaces),
      from: Formatting.civilDate(from: effectiveFrom)
    )
    if accepted {
      dismiss()
    } else {
      rejection = model.failure
      model.failure = nil
    }
  }
}
