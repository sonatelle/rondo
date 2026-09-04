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

  @State private var rejection: String?

  private let templates = serviceTemplates()

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
  }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TemplatePicker(
            templates: templates,
            categories: model.categories,
            selection: $templateID,
            name: $name,
            categoryID: $categoryID
          )
          TextField("Name", text: $name)
        }

        Section("Price") {
          HStack {
            TextField("Amount", text: $amount)
              .monospacedDigit()
            // Picked rather than typed. The core rejects anything that is
            // not three uppercase letters, and a text field's way of
            // saying so is to refuse the whole form after the fact.
            Picker("Currency", selection: $currency) {
              ForEach(Currencies.including(currency), id: \.self) { code in
                Text(code).tag(code)
              }
            }
            .labelsHidden()
            .frame(width: 120)
          }
        }

        Section("Renews") {
          HStack {
            Text("Every")
            Stepper(value: $cycleCount, in: 1 ... 100) {
              // A bare number, not prose: `Text("\(cycleCount)")` would put
              // "%lld" in the string catalogue as something to translate.
              Text(cycleCount, format: .number).monospacedDigit()
            }
            // Named for the accessibility tree even though the label is
            // hidden; an empty title would land in the catalogue as a
            // blank string waiting to be translated.
            Picker("Billing cycle unit", selection: $cycleUnit) {
              Text(cycleCount == 1 ? "day" : "days").tag(CycleUnit.day)
              Text(cycleCount == 1 ? "week" : "weeks").tag(CycleUnit.week)
              Text(cycleCount == 1 ? "month" : "months").tag(CycleUnit.month)
              Text(cycleCount == 1 ? "year" : "years").tag(CycleUnit.year)
            }
            .labelsHidden()
          }
          DatePicker(
            "First charge",
            selection: $firstBillingDate,
            displayedComponents: .date
          )
        }

        Section {
          Picker("Category", selection: $categoryID) {
            Text("None").tag(Uuid?.none)
            Divider()
            ForEach(model.categories, id: \.id) { category in
              Label {
                Text(verbatim: Categories.name(category.name, iconKey: category.iconKey))
              } icon: {
                Image(systemName: Categories.symbol(for: category.iconKey))
                  .foregroundStyle(Categories.tint(for: category.colorKey))
              }
              .tag(Uuid?.some(category.id))
            }
          }
        }

        Section("Notes") {
          TextField("Optional", text: $notes, axis: .vertical)
            .lineLimit(2 ... 4)
        }

        if let rejection {
          Text(rejection)
            .foregroundStyle(.red)
            .font(.callout)
        }
      }
      .formStyle(.grouped)

      Divider()
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(editing == nil ? "Add" : "Save") { save() }
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amount.isEmpty)
      }
      .padding(12)
    }
    .frame(width: 420, height: 520)
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
          reminderLeadDays: nil
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

/// Picks a bundled service, filling in what it can so the person need not.
private struct TemplatePicker: View {
  let templates: [ServiceTemplate]
  /// The categories to match a template's own against.
  let categories: [Category]
  @Binding var selection: String?
  @Binding var name: String
  @Binding var categoryID: Uuid?

  var body: some View {
    Picker("Service", selection: $selection) {
      Text("Custom").tag(String?.none)
      Divider()
      ForEach(templates, id: \.id) { template in
        Text(template.name).tag(String?.some(template.id))
      }
    }
    .onChange(of: selection) { _, new in
      // Only fill untouched fields: a chosen template should never
      // overwrite something the person already decided.
      guard let new, let template = templates.first(where: { $0.id == new }) else { return }
      if name.isEmpty {
        name = template.name
      }
      if categoryID == nil {
        // The template names a category by the same key its icon carries,
        // which is how picking Netflix knows to file it under Video. A
        // category the person has since deleted simply does not match, and
        // the field is left for them to answer.
        categoryID = categories.first { $0.iconKey == template.defaultCategory }?.id
      }
    }
  }
}
