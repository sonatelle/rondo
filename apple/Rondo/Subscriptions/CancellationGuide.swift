import SwiftUI

/// Where to go to stop paying for something.
///
/// Rondo cannot cancel anything - it is a record of what renews, with no
/// account anywhere and no business holding one. What it can do is answer
/// the question that follows "I should stop paying for this": where do I
/// go? The answer depends entirely on where the subscription was bought,
/// which is why the form asks.
///
/// Nothing here is a link to a cancellation page. A deep link to the right
/// page of the right account is exactly the sort of thing that rots between
/// releases, and a button that lands somewhere unhelpful is worse than a
/// sentence saying where to look. Where a service's own page is recorded
/// one day, this is where it goes.
struct CancellationGuide: View {
  let model: SubscriptionsModel
  let renewal: Renewal

  /// Archiving is offered here because it is what somebody wants a minute
  /// after cancelling, and coming back for it is a step easy to forget -
  /// which is how a cancelled subscription goes on being counted.
  let archive: () -> Void

  @Environment(\.dismiss) private var dismiss

  private var subscription: Subscription {
    renewal.subscription
  }

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: String(localized: "How to cancel \(subscription.name)",
                              bundle: bundle, locale: locale,
                              comment: "Title of the cancellation guide"))
          .font(.system(size: 17, weight: .semibold))
        Text(verbatim: lead)
          .font(Theme.Font.body)
          .foregroundStyle(Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, Theme.Space.block)
      .padding(.top, Theme.Space.section)
      .padding(.bottom, Theme.Space.xl)

      body(for: subscription.channel)
        .padding(.horizontal, Theme.Space.xxl)

      if let warning {
        Text(verbatim: warning)
          .font(Theme.Font.caption)
          .foregroundStyle(Color.warnForeground)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(Theme.Space.xl)
          .background(Color.warnBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
          .padding(.horizontal, Theme.Space.xxl)
          .padding(.top, Theme.Space.l)
      }

      footer
    }
    .frame(width: 460)
    .background(Color.surface)
  }

  /// What kind of answer this is going to be, said before the steps so
  /// somebody knows whether they are about to leave the app.
  private var lead: String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch subscription.channel {
    case .appStore:
      String(localized: "This one is billed through the App Store, so it is cancelled there.",
             bundle: bundle, locale: locale, comment: "Under the cancellation guide's title")
    case .googlePlay:
      String(localized: "This one is billed through Google Play, so it is cancelled there.",
             bundle: bundle, locale: locale, comment: "Under the cancellation guide's title")
    case .web, .other, .none:
      String(localized: "This one is billed by the service itself, so it is cancelled in your account with them.",
             bundle: bundle, locale: locale, comment: "Under the cancellation guide's title")
    }
  }

  @ViewBuilder
  private func body(for channel: Channel?) -> some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    switch channel {
    case .appStore:
      steps([
        String(localized: "Open System Settings › Apple Account › Subscriptions",
               bundle: bundle, locale: locale, comment: "Cancelling through the App Store"),
        String(localized: "Find this subscription and choose Cancel Subscription",
               bundle: bundle, locale: locale, comment: "Cancelling through a store"),
        String(localized: "Come back and archive it here", bundle: bundle, locale: locale,
               comment: "The last step of every cancellation guide"),
      ])
    case .googlePlay:
      steps([
        String(localized: "On an Android device, open Play Store › Payments and subscriptions",
               bundle: bundle, locale: locale, comment: "Cancelling through Google Play"),
        String(localized: "Find this subscription and choose Cancel Subscription",
               bundle: bundle, locale: locale, comment: "Cancelling through a store"),
        String(localized: "Come back and archive it here", bundle: bundle, locale: locale,
               comment: "The last step of every cancellation guide"),
      ])
    case .web, .other, .none:
      account
    }
  }

  /// Numbered, because the order matters and because a wall of prose is
  /// what people skip when they are already annoyed.
  private func steps(_ lines: [String]) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
        if index > 0 {
          Divider()
        }
        HStack(alignment: .top, spacing: Theme.Space.l) {
          Text(verbatim: "\(index + 1)")
            .font(Theme.Font.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(Color.iconBlueForeground)
            .frame(width: 20, height: 20)
            .background(Color.iconBlueBackground, in: Circle())
          Text(verbatim: line)
            .font(Theme.Font.body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
      }
    }
    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
  }

  /// What somebody needs in front of them to sign in and cancel: which
  /// account it bills to, and which card is paying. Both are what Rondo was
  /// told; neither is offered when nobody said.
  private var account: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    let method = subscription.paymentMethodId
      .flatMap { id in model.paymentMethods.first { $0.id == id } }
    return VStack(spacing: 0) {
      Text(verbatim: String(
        localized: "Sign in to the service and cancel there. Rondo has no account with them and cannot do it for you.",
        bundle: bundle, locale: locale, comment: "The generic cancellation guidance"
      ))
      .font(Theme.Font.body)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Theme.Space.xl)
      .padding(.vertical, Theme.Space.l)

      if let account = subscription.account, !account.isEmpty {
        Divider()
        row(String(localized: "Account", bundle: bundle, locale: locale,
                   comment: "Form row: the account it bills to"), account, copyable: true)
      }
      if let method {
        Divider()
        row(String(localized: "Paid with", bundle: bundle, locale: locale,
                   comment: "Form row: which card or account pays for it"),
            PaymentMethods.name(method.name), copyable: false)
      }
    }
    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
  }

  private func row(_ label: String, _ value: String, copyable: Bool) -> some View {
    HStack(spacing: Theme.Space.xl) {
      Text(verbatim: label)
        .font(Theme.Font.label)
        .foregroundStyle(Color.textSecondary)
        .frame(width: 96, alignment: .leading)
      Text(verbatim: value)
        .font(Theme.Font.body)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
      if copyable {
        Button {
          // Straight to the clipboard, because the next thing this is
          // needed for is a sign-in field in a browser.
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(value, forType: .string)
        } label: {
          Text(verbatim: String(localized: "Copy", bundle: Localization.bundle,
                                locale: Localization.locale,
                                comment: "Puts a value on the clipboard"))
            .font(Theme.Font.caption)
            .foregroundStyle(Color.linkText)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, Theme.Space.xl)
    .padding(.vertical, Theme.Space.l)
  }

  /// Said only when it is nearly true. A charge a month off is not a reason
  /// to hurry, and a warning that is always on stops being read.
  private var warning: String? {
    let urgency = Urgency.of(renewal.date, from: model.referenceDay)
    guard urgency != .distant else { return nil }
    return String(
      localized: "It is charged again on \(Formatting.date(renewal.date)). Cancelling keeps what you have already paid for until then.",
      bundle: Localization.bundle, locale: Localization.locale,
      comment: "Warning when the next charge is near"
    )
  }

  private var footer: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return HStack(spacing: Theme.Space.s) {
      Spacer()
      if subscription.status == .active {
        Button(String(localized: "Archive it now", bundle: bundle, locale: locale,
                      comment: "Stops counting the subscription, from the guide"))
        {
          archive()
          dismiss()
        }
      }
      Button(String(localized: "Done", bundle: bundle, locale: locale,
                    comment: "Closes the cancellation guide")) { dismiss() }
        .keyboardShortcut(.defaultAction)
    }
    .padding(.horizontal, Theme.Space.block)
    .padding(.vertical, Theme.Space.card)
  }
}
