import SwiftUI

/// The sheet for recording a subscription, or for changing one.
///
/// One form serves both so the fields, their order, and their validation
/// cannot drift apart between adding and editing.
///
/// It collects text and hands it to the core, which decides whether it is
/// acceptable. Nothing is validated twice: a rejected value comes back in
/// the core's own words, so the two sides cannot disagree about what
/// counts as a valid amount or cycle.
struct SubscriptionFormView: View {
  let model: SubscriptionsModel

  /// The subscription being changed, or nothing when adding one.
  let editing: Subscription?

  @Environment(\.dismiss) private var dismiss

  @State private var name: String
  @State private var amount: String
  @State private var currency: String
  @State private var cycleCount: Int
  @State private var cycleUnit: CycleUnit
  @State private var firstBillingDate: Date
  @State private var notes: String
  @State private var templateID: String?

  /// Which category this is filed under, or none.
  ///
  /// `nil` is a real answer and stays available: a subscription that fits
  /// nowhere should not have to be forced into a category, and the sidebar
  /// counts what is filed rather than demanding everything be.
  @State private var categoryID: Uuid?

  /// Where it was bought, which decides where it is cancelled.
  @State private var channel: Channel?

  /// The account it bills to, as the person writes it.
  @State private var account: String

  @State private var paymentMethodID: Uuid?

  /// Whether to be told before a charge, and how far ahead.
  @State private var reminds: Bool
  @State private var reminderLeadDays: Int

  @State private var rejection: String?

  init(model: SubscriptionsModel, editing: Subscription? = nil) {
    self.model = model
    self.editing = editing
    _name = State(initialValue: editing?.name ?? "")
    _amount = State(initialValue: editing?.amount ?? "")
    // A new subscription starts in this Mac's own currency. Naming one
    // here would be right for whoever picked it and wrong for everyone
    // else.
    _currency = State(initialValue: editing?.currency ?? Currencies.preferred)
    _cycleCount = State(initialValue: Int(editing?.cycleCount ?? 1))
    _cycleUnit = State(initialValue: editing?.cycleUnit ?? .month)
    _firstBillingDate = State(
      initialValue: editing.flatMap { Formatting.parseCivilDate($0.firstBillingDate) } ?? Date()
    )
    _notes = State(initialValue: editing?.notes ?? "")
    _templateID = State(initialValue: editing?.templateId)
    _categoryID = State(initialValue: editing?.categoryId)
    _channel = State(initialValue: editing?.channel)
    _account = State(initialValue: editing?.account ?? "")
    _paymentMethodID = State(initialValue: editing?.paymentMethodId)
    // A lead of zero is how "do not remind me" is stored, so the toggle is
    // a reading of the number rather than a second thing to keep in step.
    let lead = Int(editing?.reminderLeadDays ?? 3)
    _reminds = State(initialValue: lead > 0)
    _reminderLeadDays = State(initialValue: lead > 0 ? lead : 3)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          FormCard { rows }
            .padding(.horizontal, Theme.Space.xxl)

          // Only when editing. A subscription being added has no history
          // yet - the core opens one when it is inserted - and a card that
          // could only say "nothing here" is worse than no card.
          if let editing {
            Text(verbatim: String(localized: "Price history", bundle: Localization.bundle,
                                  locale: Localization.locale,
                                  comment: "Heading of the card listing past prices"))
              .font(Theme.Font.groupTitle)
              .foregroundStyle(Color.textMuted)
              .padding(.horizontal, Theme.Space.block)
              .padding(.top, Theme.Space.xxl)
              .padding(.bottom, Theme.Space.m)
            FormCard { PriceHistoryCard(model: model, subscription: editing) }
              .padding(.horizontal, Theme.Space.xxl)
          }

          if let rejection {
            Text(rejection)
              .font(Theme.Font.caption)
              .foregroundStyle(Color.danger)
              .padding(.horizontal, Theme.Space.block)
              .padding(.top, Theme.Space.xxl)
          }
        }
        .padding(.bottom, Theme.Space.xxl)
      }
      footer
    }
    .frame(width: 640, height: 620)
    .background(Color.surface)
  }

  @ViewBuilder
  private var rows: some View {
    // Every word here is looked up rather than written as a key. A key
    // handed to `Text` resolves against the system's language, so a form
    // in an app set to English came out in the language the Mac was set
    // to; `Localization.bundle` is the language the person chose.
    let bundle = Localization.bundle
    let locale = Localization.locale

    FormRow(label: String(localized: "Service", bundle: bundle, locale: locale,
                          comment: "Form row: which service this subscription is"))
    {
      ProviderPicker(
        categories: model.categories,
        recents: model.recentProviders,
        selection: $templateID,
        name: $name,
        categoryID: $categoryID
      )
    }
    FormDivider()

    FormRow(label: String(localized: "Name", bundle: bundle, locale: locale,
                          comment: "Form row: what this subscription is called"),
            spacing: Theme.Space.xxl)
    {
      FormField(text: $name)
      FormNote(text: String(localized: "required", bundle: bundle, locale: locale,
                            comment: "Beside a field that must be filled in"))
    }
    FormDivider()

    FormRow(label: String(localized: "Price", bundle: bundle, locale: locale,
                          comment: "Form row: what it costs each cycle"),
            spacing: Theme.Space.l)
    {
      FormField(text: $amount, width: 96)
      // Picked rather than typed. The core rejects anything that is not
      // three uppercase letters, and a text field's way of saying so is to
      // refuse the whole form after the fact.
      CurrencyMenu(currency: $currency)
      Spacer(minLength: Theme.Space.m)
      FormNote(text: String(localized: "Currencies are never converted", bundle: bundle,
                            locale: locale, comment: "Beside the currency, in the form"))
    }
    FormDivider()

    FormRow(label: String(localized: "Renews", bundle: bundle, locale: locale,
                          comment: "Form row: how often it is charged"),
            spacing: Theme.Space.l)
    {
      Text(verbatim: String(localized: "Every", bundle: bundle, locale: locale,
                            comment: "Reads as 'every 3 months'; the count follows"))
        .font(Theme.Font.body)
        .foregroundStyle(Color.textSecondary)
      FormField(text: cycleCountText, width: 46, alignment: .center)
      Picker(selection: $cycleUnit) {
        Text(verbatim: String(localized: "Months", bundle: bundle, locale: locale,
                              comment: "Billing cycle unit")).tag(CycleUnit.month)
        Text(verbatim: String(localized: "Weeks", bundle: bundle, locale: locale,
                              comment: "Billing cycle unit")).tag(CycleUnit.week)
        Text(verbatim: String(localized: "Days", bundle: bundle, locale: locale,
                              comment: "Billing cycle unit")).tag(CycleUnit.day)
        Text(verbatim: String(localized: "Years", bundle: bundle, locale: locale,
                              comment: "Billing cycle unit")).tag(CycleUnit.year)
      } label: {
        EmptyView()
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      Spacer(minLength: 0)
    }
    FormDivider()

    FormRow(label: String(localized: "First charge", bundle: bundle, locale: locale,
                          comment: "Form row: the day the schedule is anchored to"))
    {
      DateField(date: $firstBillingDate)
      if let monthEndNote {
        FormNote(text: monthEndNote, speaking: true)
      }
      Spacer(minLength: 0)
    }
    FormDivider()

    FormRow(label: String(localized: "Bought through", bundle: bundle, locale: locale,
                          comment: "Form row: where the subscription was bought"))
    {
      // Label-less rather than a hidden label: a label nobody sees still
      // reaches the string catalogue, where it is a key no translator can
      // place. The row's own label is the label.
      Picker(selection: $channel) {
        // The two stores keep their own names in every language; the other
        // two are ordinary words and are translated.
        Text(verbatim: "App Store").tag(Channel?.some(.appStore))
        Text(verbatim: "Google Play").tag(Channel?.some(.googlePlay))
        Text(verbatim: String(localized: "Its own site", bundle: bundle, locale: locale,
                              comment: "Bought from the service's own site or app"))
          .tag(Channel?.some(.web))
        Text(verbatim: String(localized: "Elsewhere", bundle: bundle, locale: locale,
                              comment: "Bought somewhere none of the other choices name"))
          .tag(Channel?.some(.other))
      } label: {
        EmptyView()
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      Spacer(minLength: Theme.Space.m)
      FormNote(text: String(localized: "Decides where you cancel it", bundle: bundle,
                            locale: locale, comment: "Beside the channel, in the form"))
    }
    FormDivider()

    FormRow(label: String(localized: "Account", bundle: bundle, locale: locale,
                          comment: "Form row: the account it bills to"),
            spacing: Theme.Space.l)
    {
      FormField(text: $account)
      FormNote(text: String(localized: "optional", bundle: bundle, locale: locale,
                            comment: "Beside a field that may be left empty"))
    }
    FormDivider()

    FormRow(label: String(localized: "Paid with", bundle: bundle, locale: locale,
                          comment: "Form row: which card or account pays for it"),
            spacing: Theme.Space.l)
    {
      Picker(selection: $paymentMethodID) {
        Text(verbatim: String(localized: "Not recorded", bundle: bundle, locale: locale,
                              comment: "No payment method was said"))
          .tag(Uuid?.none)
        ForEach(model.paymentMethods, id: \.id) { method in
          Text(verbatim: method.name).tag(Uuid?.some(method.id))
        }
      } label: {
        EmptyView()
      }
      .labelsHidden()
      .fixedSize()
      FormNote(text: String(localized: "Subscriptions on one card are grouped together",
                            bundle: bundle, locale: locale,
                            comment: "Beside the payment method, in the form"),
               speaking: true)
      Spacer(minLength: 0)
    }
    FormDivider()

    FormRow(label: String(localized: "Category", bundle: bundle, locale: locale,
                          comment: "Form row: what the subscription is filed under"))
    {
      // Chips rather than a menu: there are eight of them, they fit, and a
      // menu would hide which one is chosen behind a click.
      CategoryChips(categories: model.categories, selection: $categoryID)
      Spacer(minLength: 0)
    }
    FormDivider()

    FormRow(label: String(localized: "Remind me", bundle: bundle, locale: locale,
                          comment: "Form row: whether to be told before a charge"))
    {
      Toggle(isOn: $reminds) { EmptyView() }
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
      if reminds {
        Stepper(value: $reminderLeadDays, in: 1 ... 30) {
          // Asked for whole rather than joined from a number and a word:
          // a language that inflects the noun for the count has nowhere to
          // say so once the two have been glued together.
          Text(verbatim: String(localized: "\(reminderLeadDays) days before the charge",
                                bundle: bundle, locale: locale,
                                comment: "How far ahead the reminder comes"))
            .font(Theme.Font.body)
        }
        .fixedSize()
      } else {
        Text(verbatim: String(localized: "Not before this one", bundle: bundle, locale: locale,
                              comment: "Shown when reminders are off for this subscription"))
          .font(Theme.Font.body)
          .foregroundStyle(Color.textMuted)
      }
      Spacer(minLength: 0)
    }
    FormDivider()

    FormRow(label: String(localized: "Notes", bundle: bundle, locale: locale,
                          comment: "Form row: anything the person wants to remember"),
            spacing: Theme.Space.l)
    {
      FormField(text: $notes)
      FormNote(text: String(localized: "optional", bundle: bundle, locale: locale,
                            comment: "Beside a field that may be left empty"))
    }
  }

  /// The title, and what the form is for.
  private var header: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(alignment: .leading, spacing: 3) {
      Text(verbatim: editing == nil
        ? String(localized: "New subscription", bundle: bundle, locale: locale,
                 comment: "Title of the form when adding")
        : String(localized: "Edit subscription", bundle: bundle, locale: locale,
                 comment: "Title of the form when changing one"))
        .font(.system(size: 17, weight: .semibold))
      Text(verbatim: String(
        localized: "Pick a service first; the name and price stay yours to change.",
        bundle: bundle, locale: locale, comment: "Form subtitle"
      ))
      .font(Theme.Font.body)
      .foregroundStyle(Color.textMuted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Theme.Space.block)
    .padding(.top, Theme.Space.section)
    .padding(.bottom, Theme.Space.xxl)
  }

  /// What this comes to a month, beside the buttons.
  ///
  /// The arithmetic is the core's: a yearly plan divided by twelve is a
  /// sum, and sums do not live on this side.
  private var footer: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return HStack(spacing: Theme.Space.l) {
      if let levelled {
        Text(verbatim: String(localized: "About \(levelled) a month", bundle: bundle,
                              locale: locale,
                              comment: "What the price comes to a month, beside the buttons"))
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textFaint)
      }
      Spacer()
      Button(String(localized: "Cancel", bundle: bundle, locale: locale,
                    comment: "Closes the form without saving"), role: .cancel) { dismiss() }
        .keyboardShortcut(.cancelAction)
      Button(editing == nil
        ? String(localized: "Add", bundle: bundle, locale: locale,
                 comment: "Saves a new subscription")
        : String(localized: "Save", bundle: bundle, locale: locale,
                 comment: "Saves a changed subscription")) { save() }
        .keyboardShortcut(.defaultAction)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amount.isEmpty)
    }
    .padding(.horizontal, Theme.Space.block)
    .padding(.vertical, Theme.Space.card)
  }

  /// What this subscription comes to a month, spread across its cycle.
  ///
  /// Asked of the core rather than divided here: a yearly plan over twelve
  /// months is a sum about money, and those do not live on this side.
  /// Absent while the amount is not yet a number to divide.
  private var levelled: String? {
    guard let monthly = model.monthlyEquivalent(
      amount: amount.trimmingCharacters(in: .whitespaces),
      currency: currency,
      cycleCount: UInt32(cycleCount),
      cycleUnit: cycleUnit
    ) else { return nil }
    return Formatting.amount(monthly, currency: currency)
  }

  /// The cycle count as text, so it can be typed rather than stepped.
  private var cycleCountText: Binding<String> {
    Binding(
      get: { String(cycleCount) },
      set: { cycleCount = max(1, min(100, Int($0.filter(\.isNumber)) ?? 1)) }
    )
  }

  /// What the month-end rule does to this particular day, said plainly
  /// rather than left for somebody to discover in February.
  private var monthEndNote: String? {
    let day = Calendar.current.component(.day, from: firstBillingDate)
    guard cycleUnit == .month, day > 28 else { return nil }
    return String(localized: "Short months fall back to their last day",
                  bundle: Localization.bundle, locale: Localization.locale,
                  comment: "Under the first charge date, when the day is 29 or later")
  }

  private func save() {
    let accepted: Bool
    if var subscription = editing {
      // Identity and timestamps stay as stored; the core refreshes
      // `updated_at` itself when it writes.
      subscription.name = name
      subscription.amount = amount.trimmingCharacters(in: .whitespaces)
      subscription.currency = currency
      subscription.cycleCount = UInt32(cycleCount)
      subscription.cycleUnit = cycleUnit
      subscription.firstBillingDate = Formatting.civilDate(from: firstBillingDate)
      subscription.notes = notes.isEmpty ? nil : notes
      subscription.templateId = templateID
      subscription.categoryId = categoryID
      subscription.channel = channel
      subscription.account = account.isEmpty ? nil : account
      subscription.paymentMethodId = paymentMethodID
      subscription.reminderLeadDays = UInt16(reminds ? reminderLeadDays : 0)
      accepted = model.update(subscription)
    } else {
      accepted = model.add(
        NewSubscription(
          name: name,
          amount: amount.trimmingCharacters(in: .whitespaces),
          currency: currency,
          cycleCount: UInt32(cycleCount),
          cycleUnit: cycleUnit,
          firstBillingDate: Formatting.civilDate(from: firstBillingDate),
          notes: notes.isEmpty ? nil : notes,
          templateId: templateID,
          categoryId: categoryID,
          channel: channel,
          account: account.isEmpty ? nil : account,
          paymentMethodId: paymentMethodID,
          reminderLeadDays: UInt16(reminds ? reminderLeadDays : 0)
        )
      )
    }
    if accepted {
      dismiss()
    } else {
      // The model has the core's message; showing it here keeps the form
      // open with the offending value still in place.
      rejection = model.failure
      model.failure = nil
    }
  }
}

// MARK: - Previews

// The sheet is a fixed size, so what these check is the content rather than
// the layout at a narrow window: that a new subscription starts empty and
// an edited one arrives filled in.

#Preview("Add a subscription") {
  SubscriptionFormView(model: PreviewData.populated())
}
