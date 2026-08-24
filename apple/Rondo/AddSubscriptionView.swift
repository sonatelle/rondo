import SwiftUI

/// The sheet for recording a subscription.
///
/// The form collects text and hands it to the core, which decides whether
/// it is acceptable. Nothing is validated twice: a rejected draft comes
/// back with the core's own words, so the two sides cannot disagree about
/// what counts as a valid amount or cycle.
struct AddSubscriptionView: View {
  let model: SubscriptionsModel
  @Environment(\.dismiss) private var dismiss

  @State private var name = ""
  @State private var amount = ""
  @State private var currency = "CNY"
  @State private var cycleCount = 1
  @State private var cycleUnit: CycleUnit = .month
  @State private var firstBillingDate = Date()
  @State private var notes = ""
  @State private var templateID: String?
  @State private var rejection: String?

  private let templates = serviceTemplates()

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TemplatePicker(templates: templates, selection: $templateID, name: $name)
          TextField("Name", text: $name)
        }

        Section("Price") {
          HStack {
            TextField("Amount", text: $amount)
              .monospacedDigit()
            TextField("Currency", text: $currency)
              .frame(width: 70)
              .textCase(.uppercase)
          }
        }

        Section("Renews") {
          HStack {
            Text("Every")
            Stepper(value: $cycleCount, in: 1 ... 100) {
              Text("\(cycleCount)").monospacedDigit()
            }
            Picker("", selection: $cycleUnit) {
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
        Button("Add") { save() }
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amount.isEmpty)
      }
      .padding(12)
    }
    .frame(width: 420, height: 520)
  }

  private func save() {
    let draft = NewSubscription(
      name: name,
      amount: amount.trimmingCharacters(in: .whitespaces),
      currency: currency.uppercased(),
      cycleCount: UInt32(cycleCount),
      cycleUnit: cycleUnit,
      firstBillingDate: Formatting.civilDate(from: firstBillingDate),
      notes: notes.isEmpty ? nil : notes,
      templateId: templateID,
      categoryId: nil,
      reminderLeadDays: nil
    )
    if model.add(draft) {
      dismiss()
    } else {
      // The model has the core's message; showing it here keeps the form
      // open with the offending value still in place.
      rejection = model.failure
      model.failure = nil
    }
  }
}

/// Picks a bundled service, filling in the name so the person need not.
private struct TemplatePicker: View {
  let templates: [ServiceTemplate]
  @Binding var selection: String?
  @Binding var name: String

  var body: some View {
    Picker("Service", selection: $selection) {
      Text("Custom").tag(String?.none)
      Divider()
      ForEach(templates, id: \.id) { template in
        Text(template.name).tag(String?.some(template.id))
      }
    }
    .onChange(of: selection) { _, new in
      // Only fill an untouched field: a chosen template should never
      // overwrite a name the person already typed.
      guard let new, let template = templates.first(where: { $0.id == new }) else { return }
      if name.isEmpty {
        name = template.name
      }
    }
  }
}
