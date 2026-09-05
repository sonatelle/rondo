import SwiftUI

/// Which card or account pays for a subscription, with a way to name a new
/// one and to remove one, without leaving the form.
///
/// Both of those are here rather than in settings because this is where
/// somebody finds out they need them: they are filling in a subscription,
/// they reach this row, and the card they paid with is either missing or
/// listed twice. A trip to a settings pane and back would lose the
/// half-filled form.
///
/// A button and a popover, like the provider picker, so the form reads as
/// one kind of control rather than several. A `Menu` was tried and cannot
/// be made to match: macOS draws its own indicator on the leading edge and
/// ignores a background on the label.
struct PaymentMethodPicker: View {
  let model: SubscriptionsModel
  @Binding var selection: Uuid?

  @State private var isPresented = false
  @State private var isNaming = false

  /// The method a click on a bin is asking about, held until the question
  /// is answered. Deleting is the one thing here that cannot be undone.
  @State private var pendingDeletion: PaymentMethod?

  var body: some View {
    Button {
      isPresented = true
    } label: {
      PickerChip(title: chosenName, minWidth: 108)
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      panel
    }
    .sheet(isPresented: $isNaming) {
      // Selected as soon as it exists: nobody names one of these except to
      // use it on the subscription they are filling in.
      PaymentMethodSheet(model: model) { selection = $0 }
    }
    .confirmationDialog(
      deletionTitle,
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: {
          if !$0 {
            pendingDeletion = nil
          }
        }
      ),
      presenting: pendingDeletion
    ) { method in
      Button(String(localized: "Delete", bundle: Localization.bundle,
                    locale: Localization.locale,
                    comment: "Confirms deleting subscriptions"), role: .destructive)
      {
        delete(method)
      }
    } message: { method in
      Text(verbatim: deletionMessage(method))
    }
  }

  private var panel: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          PickerRow(
            title: String(localized: "Not recorded", bundle: bundle, locale: locale,
                          comment: "No payment method was said"),
            isChosen: selection == nil
          ) {
            selection = nil
            isPresented = false
          }
          ForEach(model.paymentMethods, id: \.id) { method in
            PickerRow(
              title: PaymentMethods.name(method.name),
              isChosen: selection == method.id,
              choose: {
                selection = method.id
                isPresented = false
              }
            ) {
              removeButton(method)
            }
          }
        }
        .padding(Theme.Space.m)
      }
      .frame(maxHeight: 260)

      Divider().foregroundStyle(Color.separatorLine)
      Button {
        isPresented = false
        isNaming = true
      } label: {
        HStack(spacing: Theme.Space.l) {
          Image(systemName: "plus")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.textSecondary)
            .frame(width: 22, height: 22)
            .background(Color.hoverBackground, in: RoundedRectangle(cornerRadius: 6))
          Text(verbatim: String(localized: "New payment method…", bundle: bundle, locale: locale,
                                comment: "Opens the sheet that names a card or account"))
            .font(Theme.Font.body)
            .foregroundStyle(Color.textPrimary)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(Theme.Space.m)
    }
    .frame(width: 260)
    .background(Color.surface)
    .multilineTextAlignment(.leading)
  }

  private func removeButton(_ method: PaymentMethod) -> some View {
    Button {
      pendingDeletion = method
    } label: {
      Image(systemName: "trash")
        .font(.system(size: 11))
        .foregroundStyle(Color.textMuted)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(String(localized: "Delete this payment method", bundle: Localization.bundle,
                 locale: Localization.locale, comment: "Tooltip on the bin in the picker"))
  }

  /// A method's own name is data and is shown as written; the words that
  /// stand in when there is none go through the catalogue.
  private var chosenName: String {
    if let selection, let method = model.paymentMethods.first(where: { $0.id == selection }) {
      return PaymentMethods.name(method.name)
    }
    return String(localized: "Not recorded", bundle: Localization.bundle,
                  locale: Localization.locale, comment: "No payment method was said")
  }

  private var deletionTitle: String {
    guard let pendingDeletion else { return "" }
    return String(localized: "Delete \(PaymentMethods.name(pendingDeletion.name))?",
                  bundle: Localization.bundle, locale: Localization.locale,
                  comment: "Confirmation title before removing a payment method")
  }

  /// Says what deleting costs, which depends on whether anything pays by
  /// it: nothing is lost but the row, and the subscriptions that pointed at
  /// it go back to saying nobody has said how they are paid for.
  private func deletionMessage(_ method: PaymentMethod) -> String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    let count = model.allRenewals.count { $0.subscription.paymentMethodId == method.id }
    guard count > 0 else {
      return String(localized: "Nothing is paid for with it.", bundle: bundle, locale: locale,
                    comment: "Deleting a payment method nothing uses")
    }
    return String(localized: "\(count) subscriptions will go back to saying nothing.",
                  bundle: bundle, locale: locale,
                  comment: "Deleting a payment method that subscriptions point at")
  }

  private func delete(_ method: PaymentMethod) {
    // Cleared here rather than left to the core's answer: a row this form
    // has just removed cannot go on being the selected one.
    if selection == method.id {
      selection = nil
    }
    model.deletePaymentMethod(method)
    pendingDeletion = nil
  }
}

/// Names a card or an account.
///
/// One field, because that is all a payment method is: the core keeps a
/// name and an order, and deliberately nothing else. A card number would be
/// somebody's card number, and Rondo has no business holding one - which is
/// what the note under the field says, in as many words.
private struct PaymentMethodSheet: View {
  let model: SubscriptionsModel

  /// Handed the new method's id, so the row that opened this can select it.
  let onCreated: (Uuid) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var rejection: String?

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: String(localized: "New payment method", bundle: bundle, locale: locale,
                              comment: "Title of the sheet that names a card or account"))
          .font(.system(size: 15, weight: .semibold))
        Text(verbatim: String(
          localized: "Name it the way you would recognise it on a statement.",
          bundle: bundle, locale: locale,
          comment: "Subtitle of the payment method sheet"
        ))
        .font(Theme.Font.body)
        .foregroundStyle(Color.textMuted)
      }
      .padding(.horizontal, Theme.Space.block)
      .padding(.top, Theme.Space.section)
      .padding(.bottom, Theme.Space.xxl)

      FormCard {
        FormRow(label: String(localized: "Name", bundle: bundle, locale: locale,
                              comment: "Form row: what this subscription is called"),
                spacing: Theme.Space.l)
        {
          FormField(text: $name)
          FormNote(text: String(localized: "required", bundle: bundle, locale: locale,
                                comment: "Beside a field that must be filled in"))
        }
      }
      .padding(.horizontal, Theme.Space.xxl)

      Text(verbatim: String(
        localized: "Rondo keeps only the name. It never asks for a card number.",
        bundle: bundle, locale: locale,
        comment: "Under the payment method field, about what is stored"
      ))
      .font(Theme.Font.footnote)
      .foregroundStyle(Color.textFaint)
      .padding(.horizontal, Theme.Space.block)
      .padding(.top, Theme.Space.m)

      if let rejection {
        Text(verbatim: rejection)
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
        Button(String(localized: "Add", bundle: bundle, locale: locale,
                      comment: "Saves a new subscription")) { create() }
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding(.horizontal, Theme.Space.block)
      .padding(.vertical, Theme.Space.card)
    }
    .frame(width: 440)
    .background(Color.surface)
  }

  private func create() {
    guard let id = model.addPaymentMethod(named: name.trimmingCharacters(in: .whitespaces)) else {
      // The core refused it - a blank name, say. Its own words say which,
      // and the sheet stays open with what was typed.
      rejection = model.failure
      model.failure = nil
      return
    }
    onCreated(id)
    dismiss()
  }
}
