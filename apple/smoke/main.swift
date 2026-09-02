// A smoke test for the Rust bridge, run by scripts/swift-smoke-test.sh.
//
// Generating bindings only proves the generator ran. This proves the other
// half: that Swift can link the static library, call across the boundary,
// and get values back intact. It runs against an in-memory database, so it
// touches nothing the person owns.
//
// It checks behaviour that the boundary could plausibly break, not the core
// logic already covered by the Rust tests: exact amounts, thrown errors,
// and dates arriving as the day they were sent.

import Foundation

/// Reports a failed expectation and stops, so CI sees a non-zero exit.
func expect(_ condition: Bool, _ description: String) {
  if condition {
    print("  ok - \(description)")
  } else {
    FileHandle.standardError.write(Data("  FAILED - \(description)\n".utf8))
    exit(1)
  }
}

print("rondo-core \(libraryVersion())")

/// The day this script reads prices as of, standing in for the calendar day
/// an app would pass. Prices are a history now, so asking what something
/// costs means asking what it costs on some particular day.
let today: CivilDate = "2026-06-01"

let rondo = try Rondo.openInMemory()
expect(
  try rondo.subscriptions(on: today, includeArchived: true).isEmpty,
  "a new database is empty"
)

let draft = NewSubscription(
  name: "Netflix",
  amount: "15.90",
  currency: "USD",
  cycleCount: 1,
  cycleUnit: .month,
  firstBillingDate: "2026-01-31",
  notes: "family plan",
  templateId: "netflix",
  categoryId: nil,
  reminderLeadDays: nil
)
let added = try rondo.addSubscription(draft: draft)

// A double would have turned this into 15.899999...; the string form is
// the whole reason money crosses as text.
expect(added.amount == "15.90", "the amount arrives exact, trailing zero and all")
expect(added.name == "Netflix", "the name survives the crossing")
expect(added.notes == "family plan", "optional fields survive as Swift optionals")
expect(!added.id.isEmpty, "the core assigned an id")

/// The month-end rule, seen from Swift: anchored to the 31st, February
/// clamps but March returns to the 31st.
let february = try rondo.renewals(from: "2026-02-01", includeArchived: false)
expect(february.first?.date == "2026-02-28", "February clamps to the 28th")
let march = try rondo.renewals(from: "2026-03-01", includeArchived: false)
expect(march.first?.date == "2026-03-31", "March returns to the anchored 31st")

let summary = try rondo.spendingSummary(on: today)
expect(summary.count == 1 && summary[0].currency == "USD", "spending is totalled per currency")

/// A value the core refuses must arrive as a thrown Swift error, not as a
/// silently wrong record.
var rejected = draft
rejected.currency = "dollars"
do {
  _ = try rondo.addSubscription(draft: rejected)
  expect(false, "an invalid currency is rejected")
} catch let error as RondoError {
  // Error variants keep their Rust spelling, unlike record enums such as
  // CycleUnit which are lower-camel-cased on the way out.
  if case .InvalidInput = error {
    expect(true, "an invalid currency arrives as InvalidInput")
  } else {
    expect(false, "an invalid currency arrives as InvalidInput, got \(error)")
  }
}

let backup = try rondo.exportBackup()
let restored = try Rondo.openInMemory()
let report = try restored.importBackup(json: backup)
expect(report.subscriptionsAdded == 1, "a backup carries the subscription across")
expect(
  try restored.subscription(id: added.id, on: today)?.amount == "15.90",
  "the restored amount is still exact"
)

/// A price history of more than one entry, which is the whole reason this
/// round exists: what something cost in February is not what it costs in
/// April, and both have to survive the crossing.
let card = try rondo.addPaymentMethod(name: "Visa ·1234", sortOrder: 0)
var withDetails = added
withDetails.channel = .appStore
withDetails.account = "someone@example.com"
withDetails.paymentMethodId = card.id
_ = try rondo.updateSubscription(subscription: withDetails, on: today)

_ = try rondo.addPriceChange(
  subscriptionId: added.id,
  amount: "19.90",
  currency: "USD",
  effectiveFrom: "2026-04-01"
)
let history = try rondo.priceHistory(subscriptionId: added.id)
expect(history.count == 2, "a price history crosses with every entry")
expect(history[0].amount == "15.90", "the earlier price is still exact")
expect(history[1].effectiveFrom == "2026-04-01", "the day a rise took effect survives")

let inMarch = try rondo.subscription(id: added.id, on: "2026-03-31")
expect(inMarch?.amount == "15.90", "a day before the rise is priced at the old price")
let inApril = try rondo.subscription(id: added.id, on: "2026-04-01")
expect(inApril?.amount == "19.90", "the day of the rise is priced at the new price")
expect(inApril?.channel == .appStore, "an enum with no core default arrives as itself")
expect(inApril?.paymentMethodId == card.id, "the payment method it points at survives")

expect(!serviceTemplates().isEmpty, "the bundled templates are readable without a database")

/// A nickname sharing no characters with the name it finds: proof the query
/// reached the core rather than being matched, or dropped, on this side.
let nicknamed = searchServiceTemplates(query: "B站")
expect(nicknamed.count == 1, "a nickname finds its service across the bridge")
expect(nicknamed.first?.defaultCategory == "video", "a template arrives with its category")
expect(
  serviceTemplates().allSatisfy { $0.id != customTemplateId() },
  "the custom id belongs to no bundled service"
)

print("all checks passed")
