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
  // Left unsaid here on purpose: what a draft does when nobody fills these
  // in is the case every other line of this file then reads back.
  channel: nil,
  account: nil,
  paymentMethodId: nil,
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

/// The same sum over a set the caller narrowed itself, which is what a
/// filtered list needs: adding amounts is the core's job either way.
let narrowed = try rondo.levelledTotal(subscriptions: [])
expect(narrowed.isEmpty, "an empty set comes to nothing")
let everything = try rondo.subscriptions(on: today, includeArchived: false)
let totalled = try rondo.levelledTotal(subscriptions: everything)
expect(
  totalled.count == summary.count && totalled.first?.monthly == summary.first?.monthly,
  "totalling every subscription agrees with the database's own summary"
)

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

/// The aggregations, and the one property that must hold between them: a
/// month series and a window total are two views of the same charges, so
/// they cannot disagree about the sum on either side of the boundary.
let span = (from: CivilDate("2026-01-01"), to: CivilDate("2026-05-01"))
let total = try rondo.subscriptionTotal(id: added.id, until: span.to)
let series = try rondo.monthlySeries(from: span.from, to: span.to)
let window = try rondo.windowTotals(from: span.from, to: span.to)

// Charges on 31 January, 28 February and 31 March at 15.90, then 30 April
// at 19.90 - the rise recorded above. Three times 15.90 is 47.70.
expect(total.chargeCount == 4, "a cumulative counts every charge in the window")
expect(total.total == "67.60", "and prices each at the price of its own day")
expect(series.count == 4, "a month series has an entry for every month, empty or not")
expect(window.first?.total == total.total, "the window total agrees with the cumulative")
expect(
  series.reduce(Decimal.zero) { $0 + Decimal(string: $1.charged)! } == Decimal(string: window[0].total)!,
  "the months add up to the window"
)
expect(
  try rondo.earliestCharge(on: span.to) == "2026-01-31",
  "an all-time window knows where to start"
)

/// The charges themselves, which the totals above are sums of. Listing them
/// and summing them cannot disagree - the same primitive produced both.
let listed = try rondo.charges(id: added.id, from: span.from, to: span.to)
expect(listed.count == Int(total.chargeCount), "the charges listed are the charges counted")
expect(listed.first?.date == "2026-01-31", "a charge carries the day it fell due")
expect(listed.last?.amount == "19.90", "and the price in force on that day, not today's")
expect(
  listed.reduce(Decimal.zero) { $0 + Decimal(string: $1.amount)! } == Decimal(string: total.total)!,
  "the listed charges add up to the cumulative"
)

/// Exchange rates, which the app fetches and the core stores and converts.
/// Handing rates over and getting a converted total back is the whole shape
/// of that division, so it is worth proving through the packaged artifact
/// rather than only in Rust.
let base = baseCurrency()
try rondo.recordRates(rates: [
  ExchangeRate(currency: "USD", effectiveOn: "2026-01-01", rate: "1.00", isManual: false),
  ExchangeRate(currency: "USD", effectiveOn: "2026-03-01", rate: "2.00", isManual: false),
])
expect(try rondo.newestRateDay() == "2026-03-01", "the newest stored day is what a fetch resumes from")
expect(
  try rondo.convertAmount(amount: "11", currency: "USD", to: base, on: "2026-01-01") == "11",
  "an amount converts at the rate of the day asked about"
)
expect(
  try rondo.convertAmount(amount: "11", currency: "USD", to: base, on: "2025-12-31") == nil,
  "and a day before the history begins converts to nothing, never to 1:1"
)

// A typed rate outranks a fetched one, and no later fetch undoes it.
_ = try rondo.setManualRate(currency: "USD", on: "2026-01-01", rate: "4.00")
expect(
  try rondo.recordRates(rates: [
    ExchangeRate(currency: "USD", effectiveOn: "2026-01-01", rate: "1.00", isManual: false),
  ]) == 0,
  "a fetch writes nothing over a rate somebody typed"
)
expect(
  try rondo.rateInForce(currency: "USD", on: "2026-01-01")?.rate == "4.00",
  "and the typed rate is still the one in force"
)

/// The unconverted list is the part a screen must not ignore, so prove it
/// arrives rather than being flattened into a smaller total.
let converted = try rondo.convertedTotal(
  subscriptions: rondo.subscriptions(on: span.to, includeArchived: false),
  primary: "JPY",
  on: span.to
)
expect(converted.subscriptionCount == 0, "nothing converts into a currency with no rate")
expect(
  converted.unconverted.first?.currency == "USD",
  "and what could not be converted is named rather than dropped"
)

/// What a total was built from, which the footnote "including US$… at …"
/// is printed from. The rate has to arrive as the pair a person reads, not
/// as the value stored against the base.
let intoBase = try rondo.convertedTotal(
  subscriptions: rondo.subscriptions(on: span.to, includeArchived: false),
  primary: baseCurrency(),
  on: span.to
)
expect(intoBase.applied.count == 1, "a total names the currencies that went into it")
expect(intoBase.applied.first?.currency == "USD", "by their own code")
// Compared as a number, not as text: a Decimal has more than one spelling
// and which one arrives is not what this is about.
//
// Half, not a quarter. The rate typed above is January's, and this asks
// about May, where March's 2.00 is the one in force - so the pair is 1/2.
// Getting 0.25 here would mean a hand-entered rate had been treated as
// standing for every day after it rather than until the next entry.
expect(
  intoBase.applied.first.flatMap { Decimal(string: $0.rate ?? "") } == Decimal(string: "0.5"),
  "at the pair rate in force, not the 2.00 stored against the base"
    + " — got \(intoBase.applied.first?.rate ?? "nil")"
)
/// Tied to the subscription's own price rather than written out: it rose to
/// 19.90 in April, and a literal here would have to be remembered every time
/// the fixture above changes. It is a monthly cycle, so the levelled month
/// is exactly the price.
let priced = try rondo.subscription(id: added.id, on: span.to)!
expect(
  intoBase.applied.first.flatMap { Decimal(string: $0.monthly) }
    == Decimal(string: priced.amount),
  "and carrying the amount before conversion, which the footnote prints"
    + " — got \(intoBase.applied.first?.monthly ?? "nil"), priced at \(priced.amount)"
)

/// The switch the design offers: locked, each charge uses its own day's
/// rate; unlocked, all of them use one day's. Two answers to two questions.
let locked = try rondo.convertedSubscriptionTotal(
  id: added.id, primary: baseCurrency(), until: span.to, lockHistoricalRates: true
)
let unlocked = try rondo.convertedSubscriptionTotal(
  id: added.id, primary: baseCurrency(), until: span.to, lockHistoricalRates: false
)
expect(locked.chargeCount == unlocked.chargeCount, "the same charges are counted either way")
expect(
  Decimal(string: locked.total)! != Decimal(string: unlocked.total)!,
  "and a rate that moved makes the two totals differ, which is the whole point"
)

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
