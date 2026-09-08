import SwiftUI

/// Everything Rondo knows about one subscription, on one page.
///
/// Opened by double-clicking a row, which used to open the form. That was
/// the wrong door: most double-clicks are somebody asking "what is this and
/// what has it cost me", not "let me change it". Editing is still one click
/// away, from the button this page carries.
///
/// It reads rather than collects. The only things it changes are the three
/// a person decides about a subscription as a whole - whether to be
/// reminded, whether to stop counting it, and whether to be rid of it.
struct SubscriptionDetailView: View {
  let model: SubscriptionsModel

  /// The subscription and the day it is next charged, together, because
  /// this page says both and they are worked out as a pair.
  let renewal: Renewal

  /// Asks the window to open the form on this subscription. Handed up
  /// rather than presented here: a sheet on a sheet is a stack of paper
  /// nobody asked for, and the window already knows how to show the form.
  let edit: () -> Void

  /// Asks the window for the deletion it already knows how to confirm.
  let delete: () -> Void

  @Environment(\.dismiss) private var dismiss

  /// Whether the guide to cancelling this one is up.
  @State private var isCancelling = false

  private var subscription: Subscription {
    renewal.subscription
  }

  var body: some View {
    VStack(spacing: 0) {
      actions
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          header
          summary
          chargesSection
          settings
        }
        .padding(.bottom, Theme.Space.xxl)
      }
    }
    .frame(width: 660, height: 620)
    .background(Color.surface)
  }

  /// What can be done to the subscription as a whole, along the top.
  private var actions: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return HStack(spacing: Theme.Space.s) {
      Spacer()
      // Beside archiving rather than under a menu, because the two are one
      // errand: somebody who came here to stop paying will do both, and
      // the guide's own last step is to archive it.
      DetailButton(title: String(localized: "How to cancel", bundle: bundle, locale: locale,
                                 comment: "Opens the guide to cancelling this subscription"))
      {
        isCancelling = true
      }
      if subscription.status == .active {
        DetailButton(title: String(localized: "Archive", bundle: bundle, locale: locale,
                                   comment: "Context menu command"))
        {
          model.setArchived(subscription, true)
          dismiss()
        }
      } else {
        DetailButton(title: String(localized: "Restore", bundle: bundle, locale: locale,
                                   comment: "Context menu command: un-archive"))
        {
          model.setArchived(subscription, false)
          dismiss()
        }
      }
      DetailButton(title: String(localized: "Edit", bundle: bundle, locale: locale,
                                 comment: "Opens the form on this subscription"))
      {
        dismiss()
        edit()
      }
    }
    .padding(.horizontal, Theme.Space.xxl)
    .padding(.vertical, Theme.Space.l)
    .overlay(alignment: .bottom) { Divider() }
    .sheet(isPresented: $isCancelling) {
      CancellationGuide(model: model, renewal: renewal) {
        model.setArchived(subscription, true)
        dismiss()
      }
    }
  }

  /// The mark, the name, what kind of thing it is, and what it costs.
  private var header: some View {
    HStack(spacing: Theme.Space.xxl) {
      ServiceMark(name: subscription.name, side: 56)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: subscription.name)
          .font(.system(size: 22, weight: .semibold))
          .lineLimit(1)
        Text(verbatim: kind)
          .font(Theme.Font.body)
          .foregroundStyle(Color.textMuted)
          .lineLimit(1)
      }
      Spacer(minLength: Theme.Space.m)
      VStack(alignment: .trailing, spacing: 4) {
        TwoLineAmount(
          written: Formatting.amount(
            subscription.amount,
            currency: subscription.currency,
            convertedTo: Currencies.preferred,
            converted: model.convertedPrices[subscription.id]
          ),
          font: .system(size: 26, weight: .semibold)
        )
        UrgencyBadge(date: renewal.date, reference: model.referenceDay)
      }
    }
    .padding(.horizontal, Theme.Space.section)
    .padding(.vertical, Theme.Space.section)
  }

  /// What it is, in one line: the category it is filed under and how often
  /// it is charged. Either half may be missing, and the separator goes with
  /// whichever is absent.
  private var kind: String {
    let category = model.categories.first { $0.id == subscription.categoryId }
    return [
      category.map { Categories.name($0.name, iconKey: $0.iconKey) },
      renewal.cycleDescription,
    ].compactMap(\.self).joined(separator: " · ")
  }

  /// The three figures worth knowing without scrolling.
  private var summary: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    let total = model.totals[subscription.id]
    return HStack(spacing: 0) {
      cell(String(localized: "Next charge", bundle: bundle, locale: locale,
                  comment: "Table column"),
           Formatting.date(renewal.date))
      Divider()
      cell(String(localized: "First charge", bundle: bundle, locale: locale,
                  comment: "Form row: the day the schedule is anchored to"),
           Formatting.date(subscription.firstBillingDate))
      Divider()
      cell(String(localized: "Total spent", bundle: bundle, locale: locale,
                  comment: "Detail: what it has cost since the first charge"),
           total.map(spent) ?? "—")
    }
    .fixedSize(horizontal: false, vertical: true)
    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    .padding(.horizontal, Theme.Space.xxl)
  }

  /// What it has cost, and over how many charges - the second half being
  /// what stops the first from reading as a price.
  private func spent(_ total: SubscriptionTotal) -> String {
    // The converted figure leads when there is one, with the billed
    // currency after it on the same line - this cell is one line of a
    // three-across summary and has no room to stack.
    let written = Formatting.amount(
      total.total,
      currency: total.currency,
      convertedTo: Currencies.preferred,
      converted: model.convertedTotals[subscription.id]
    )
    let amount = written.secondary.map { "\(written.primary) · \($0)" } ?? written.primary
    let count = String(localized: "\(Int(total.chargeCount)) charges",
                       bundle: Localization.bundle, locale: Localization.locale,
                       comment: "How many charges make up a total")
    return "\(amount) · \(count)"
  }

  private func cell(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: label)
        .font(Theme.Font.footnote)
        .fontWeight(.semibold)
        .foregroundStyle(Color.textMuted)
      Text(verbatim: value)
        .font(Theme.Font.rowTitle)
        .monospacedDigit()
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Theme.Space.xl)
    .padding(.vertical, Theme.Space.xl)
  }

  private var chargesSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(verbatim: String(localized: "Charges", bundle: Localization.bundle,
                            locale: Localization.locale,
                            comment: "Heading over the list of charges"))
        .font(Theme.Font.groupTitle)
        .foregroundStyle(Color.textMuted)
        .padding(.horizontal, Theme.Space.section)
        .padding(.top, Theme.Space.xxl)
        .padding(.bottom, Theme.Space.m)

      VStack(spacing: 0) {
        let shown = charges.prefix(Self.chargesShown)
        ForEach(Array(shown.enumerated()), id: \.element.date) { index, charge in
          if index > 0 {
            Divider()
          }
          chargeRow(charge, previous: charges.count > index + 1 ? charges[index + 1] : nil)
        }
        if charges.count > Self.chargesShown {
          Divider()
          Text(verbatim: String(localized: "\(charges.count - Self.chargesShown) more charges",
                                bundle: Localization.bundle, locale: Localization.locale,
                                comment: "How many charges the detail page did not list"))
            .font(Theme.Font.caption)
            .foregroundStyle(Color.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
        }
      }
      .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
      .padding(.horizontal, Theme.Space.xxl)
    }
  }

  /// How many charges are worth showing before the list becomes a ledger.
  private static let chargesShown = 4

  /// Every charge up to and including the next one, newest first.
  ///
  /// Newest first because the interesting end is the recent one: what was
  /// charged last month, and what is about to be. The core produces them
  /// the other way round - it is answering a question about a range - so
  /// they are turned here rather than there.
  private var charges: [Charge] {
    model.charges(
      of: subscription,
      from: subscription.firstBillingDate,
      // The day after the next charge, so the next charge is inside the
      // half-open range and this page can show what is coming.
      to: SubscriptionsModel.day(after: renewal.date, days: 1)
    )
    .reversed()
  }

  /// One charge: when, whether it has happened, and what it cost.
  ///
  /// A rise is marked where it happened rather than only in the price
  /// history, because this is the list somebody scans to answer "when did
  /// this get more expensive". The difference is worked out from two
  /// amounts the core gave, in the same currency - arithmetic about
  /// display, not about money.
  private func chargeRow(_ charge: Charge, previous: Charge?) -> some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    let isFuture = charge.date > model.referenceDay
    var note = isFuture
      ? String(localized: "Expected", bundle: bundle, locale: locale,
               comment: "A charge that has not happened yet")
      : String(localized: "Charged", bundle: bundle, locale: locale,
               comment: "A charge that has already been taken")
    if let previous,
       let now = Formatting.decimal(charge.amount),
       let before = Formatting.decimal(previous.amount),
       now > before
    {
      let rise = Formatting.amount("\(now - before)", currency: charge.currency)
      note = String(localized: "\(note) · up \(rise)", bundle: bundle, locale: locale,
                    comment: "A charge, and the rise that took effect with it")
    }
    return HStack(spacing: Theme.Space.xl) {
      Text(verbatim: Formatting.date(charge.date))
        .font(Theme.Font.label)
        .monospacedDigit()
        .fontWeight(isFuture ? .semibold : .regular)
        .foregroundStyle(isFuture ? Color.urgentForeground : Color.textPrimary)
        .frame(width: 116, alignment: .leading)
      Text(verbatim: note)
        .font(Theme.Font.label)
        .foregroundStyle(Color.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
      // Converted at the rate of the day this charge fell on, not today's.
      // That is the whole reason the rates are a history, and it is most
      // visible here: two charges of the same price years apart can differ
      // in the primary currency, and that is the truth about them.
      TwoLineAmount(
        written: Formatting.amount(
          charge.amount,
          currency: charge.currency,
          convertedTo: Currencies.preferred,
          converted: model.converted(charge.amount, currency: charge.currency, on: charge.date)
        ),
        font: Theme.Font.label
      )
    }
    .padding(.horizontal, Theme.Space.xl)
    .padding(.vertical, Theme.Space.l)
  }

  /// The two decisions about the subscription rather than about its money.
  private var settings: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(spacing: 0) {
      HStack(spacing: Theme.Space.xl) {
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: String(localized: "Reminder", bundle: bundle, locale: locale,
                                comment: "Detail row: being told before a charge"))
            .font(Theme.Font.body)
          Text(verbatim: reminderNote)
            .font(Theme.Font.footnote)
            .foregroundStyle(Color.textMuted)
        }
        Spacer(minLength: 0)
        Toggle(isOn: reminds) { EmptyView() }
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
      }
      .padding(.horizontal, Theme.Space.xl)
      .padding(.vertical, Theme.Space.xl)

      Divider()

      Button {
        dismiss()
        delete()
      } label: {
        HStack(spacing: Theme.Space.xl) {
          Text(verbatim: String(localized: "Delete this subscription…", bundle: bundle,
                                locale: locale, comment: "Detail row: removes it for good"))
            .font(Theme.Font.body)
            .foregroundStyle(Color.danger)
          Spacer(minLength: Theme.Space.m)
          Text(verbatim: String(localized: "Archiving is safer; the record is kept",
                                bundle: bundle, locale: locale,
                                comment: "Beside the delete row, in the detail page"))
            .font(Theme.Font.footnote)
            .foregroundStyle(Color.textFaint)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.xl)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    .padding(.horizontal, Theme.Space.xxl)
    .padding(.top, Theme.Space.xxl)
  }

  /// How far ahead the reminder comes, or that there is none.
  private var reminderNote: String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    guard subscription.reminderLeadDays > 0 else {
      return String(localized: "Not before this one", bundle: bundle, locale: locale,
                    comment: "Shown when reminders are off for this subscription")
    }
    return String(localized: "\(Int(subscription.reminderLeadDays)) days before the charge",
                  bundle: bundle, locale: locale, comment: "How far ahead the reminder comes")
  }

  /// Turning the reminder off stores a lead of zero, which is how the core
  /// says "do not". Turning it back on restores the same three days a new
  /// subscription starts with, since the number it had is gone.
  private var reminds: Binding<Bool> {
    Binding(
      get: { subscription.reminderLeadDays > 0 },
      set: { wanted in
        var changed = subscription
        changed.reminderLeadDays = wanted ? 3 : 0
        _ = model.update(changed)
      }
    )
  }
}

// MARK: - Previews

// The sheet is a fixed size, so what this checks is the content: a
// subscription with a year of charges behind it, which is the only way to
// see the list, the cumulative and a rise all at once.

#Preview("Subscription detail") {
  let model = PreviewData.populated()
  return SubscriptionDetailView(
    model: model,
    renewal: model.upcoming.first ?? model.allRenewals[0],
    edit: {},
    delete: {}
  )
}

/// One of the buttons along the top of the detail page.
///
/// Drawn rather than left to `.bordered`, for the reason the toolbar's
/// buttons are: the design gives these their own height and radius, and a
/// row of system buttons beside our own chips reads as two applications.
private struct DetailButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(verbatim: title)
        .font(Theme.Font.caption)
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color.hoverBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
