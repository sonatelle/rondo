import Foundation
import Observation

/// The app's view of the subscription data.
///
/// Every rule lives in the Rust core; this holds the open database, keeps
/// the last-read values for SwiftUI to observe, and turns a failed call
/// into something the interface can show. It deliberately does no
/// arithmetic of its own.
@Observable
final class SubscriptionsModel {
  private let rondo: Rondo

  /// Subscriptions with the date each is next charged, narrowed to what
  /// the sidebar is showing and ordered by whichever column was clicked.
  private(set) var renewals: [Renewal] = []

  /// Everything the core returned, before the sidebar narrowed it.
  private(set) var allRenewals: [Renewal] = []

  /// The next charges, soonest first, whatever the window is filtered to.
  ///
  /// The status item asks about the world rather than about this window's
  /// current view, so it must not read `renewals`.
  var upcoming: [Renewal] {
    allRenewals
      .filter { $0.subscription.status == .active }
      .sorted { $0.date < $1.date }
  }

  /// Spending totals, one entry per currency.
  ///
  /// Still read, and still shown: `converted` is the headline figure now,
  /// but a database with no rates in it converts nothing, and a screen
  /// falling back to these is telling the truth where a single 0 would not.
  private(set) var summaries: [SpendingSummary] = []

  /// The same spending as one figure in the primary currency.
  ///
  /// `unconverted` names whatever no rate could reach. A screen showing the
  /// headline must show that too - a total quietly missing three
  /// subscriptions looks exactly like a total that is simply smaller.
  private(set) var converted: ConvertedSpending?

  /// The currency every converted figure here is in.
  ///
  /// Held rather than read from the defaults at each use, and this is the
  /// whole reason: `Currencies.preferred` is a plain lookup, so a view
  /// that calls it gives SwiftUI nothing to notice when it changes. Rates
  /// on screen went on saying "USD" after the setting moved to CNY, and
  /// the window only caught up when something else forced a redraw.
  ///
  /// Read from the same place as before, once, on every reload. Views ask
  /// the model, which they are already observing.
  private(set) var primaryCurrency: String = Currencies.preferred

  /// What the settings list shows for one currency.
  struct RateReading: Equatable {
    /// What one unit of it buys of the primary currency, or nothing when
    /// no rate reaches today.
    let pair: DecimalString?
    /// Whether the rate behind it was typed rather than fetched.
    let isManual: Bool
  }

  /// Bumped every time the stored rates may have changed.
  ///
  /// Read by the query methods below, and that is its whole purpose. A
  /// view calling `converted(_:currency:on:)` in its body is asking the
  /// database a question, which registers no dependency with SwiftUI - so
  /// a fetch landing a second later changed nothing on screen. Touching an
  /// observable property inside the query gives the calling body something
  /// to depend on, and the tracking is dynamic, so it works no matter
  /// which view made the call.
  ///
  /// It is a counter rather than a date because it has to change even when
  /// the newest day does not: fetching a currency for the first time when
  /// others already have today's rate moves nothing else.
  private(set) var ratesVersion = 0

  /// A reading for every currency the settings list shows.
  ///
  /// Held here for the same reason `primaryCurrency` is. A row that called
  /// `rates(for:)` in its body was making an FFI call, not reading
  /// observable state, so a fetch landing a second later changed nothing
  /// on screen: switching to a currency never seen before left every field
  /// blank under a note saying the rates had just been updated.
  private(set) var rateReadings: [String: RateReading] = [:]

  /// Each subscription's price in the primary currency, by id.
  ///
  /// Worked out once per reload rather than per row drawn: a table redraws
  /// on every scroll and hover, and a rate lookup for each row each time
  /// would be work repeated for an answer that cannot have changed.
  ///
  /// A subscription is absent when no rate reaches its currency. That is
  /// the case the amount rules care about most - it means one line showing
  /// what it is really billed at, never a converted-looking figure.
  private(set) var convertedPrices: [Uuid: DecimalString] = [:]

  /// Each subscription's cumulative total in the primary currency, by id.
  ///
  /// Not the same conversion as `convertedPrices`: a cumulative is summed
  /// charge by charge at the rate each fell due under, so it cannot be got
  /// by converting the total afterwards at today's rate. The core does
  /// that walk; this holds the answer.
  private(set) var convertedTotals: [Uuid: DecimalString] = [:]

  /// The most recent day any exchange rate is stored for, or nothing when
  /// none has ever been fetched.
  private(set) var newestRateDay: CivilDate?

  /// True while a fetch is in flight, so the button can say so.
  private(set) var isRefreshingRates = false

  /// Why the last rate fetch failed, in words a settings screen can show.
  ///
  /// Kept apart from `failure`, which is about the database. A rate fetch
  /// failing is ordinary - laptops go offline - and must not read like the
  /// person's data is in trouble.
  var rateFailure: String?

  /// How the last fetch went when it did not fail.
  ///
  /// A fetch that finds nothing to do is the *common* case - press Update
  /// twice and the second one has nothing left to ask for - and it used to
  /// return in silence. Pressing a button and having nothing whatever
  /// happen reads as a broken button, and it was reported as one.
  var rateNote: String?

  /// The day the loaded renewals were reckoned against.
  ///
  /// Kept rather than re-read from the clock, because "in 3 days" has to
  /// be measured against the same day the core was asked about. Reading
  /// the clock in each view would let a window left open overnight colour
  /// one row against yesterday and the next against today.
  private(set) var referenceDay: CivilDate = SubscriptionsModel.today()

  /// How many subscriptions each sidebar entry would show.
  ///
  /// Shown as counts beside the entries, and it is what lets an empty list
  /// say whether there is nothing at all or only nothing here.
  private(set) var counts: [Navigation: Int] = [:]

  /// The categories to file subscriptions under, in the order they are
  /// arranged. Every database is seeded with a set of them.
  private(set) var categories: [Category] = []

  /// The ways of paying that have been recorded, in the order arranged.
  private(set) var paymentMethods: [PaymentMethod] = []

  /// The bundled services this database already uses, most recently added
  /// first.
  ///
  /// What the provider picker offers above the rest. Derived from the
  /// subscriptions rather than remembered separately: a list of what you
  /// have picked before is already written down, and a second copy of it
  /// would be one more thing to keep true.
  var recentProviders: [ServiceTemplate] {
    let catalogue = searchServiceTemplates(query: "")
    var seen: Set<String> = []
    return allRenewals
      .sorted { $0.subscription.createdAt > $1.subscription.createdAt }
      .compactMap { $0.subscription.templateId }
      .filter { seen.insert($0).inserted }
      .compactMap { id in catalogue.first { $0.id == id } }
  }

  /// What actually falls due in the next thirty days, per currency.
  ///
  /// Charged rather than levelled: this card answers "what will leave my
  /// account", and a yearly plan that renews next week is the whole of it
  /// rather than a twelfth.
  private(set) var next30Days: [WindowTotal] = []

  /// The same window as one figure in the primary currency.
  ///
  /// Nothing when the call failed. A screen falls back to `next30Days`
  /// rather than showing a zero, the same as everywhere else.
  private(set) var next30DaysConverted: ConvertedWindow?

  /// What each subscription has cost since its first charge, most first.
  ///
  /// Cumulative, at the prices each charge was made at - which is what the
  /// price history exists for. A subscription that has not been charged yet
  /// is left out: nothing has been spent on it to rank.
  private(set) var topSpending: [(subscription: Subscription, total: SubscriptionTotal)] = []

  /// What each subscription has cost, to look up by id.
  ///
  /// The same answers `topSpending` ranks, kept in a form a table row can
  /// ask a question of: a row knows its own subscription and nothing about
  /// where it came in a ranking. Subscriptions not charged yet are absent,
  /// which is a different thing from having cost nothing.
  private(set) var totals: [Uuid: SubscriptionTotal] = [:]

  /// The ways of paying, by id, for a row that holds only the id.
  var paymentMethodsByID: [Uuid: PaymentMethod] {
    Dictionary(uniqueKeysWithValues: paymentMethods.map { ($0.id, $0) })
  }

  /// The last failure, for the interface to show and the person to dismiss.
  var failure: String?

  /// Which page the window is showing.
  var navigation: Navigation = .overview {
    didSet { reload() }
  }

  init(rondo: Rondo) {
    self.rondo = rondo
    reload()
  }

  /// Opens the database in the app's data directory.
  static func opening() throws -> SubscriptionsModel {
    let url = try Database.fileURL()
    return try SubscriptionsModel(rondo: Rondo.open(path: url.path(percentEncoded: false)))
  }

  /// Re-reads everything the interface displays.
  ///
  /// The core is asked for today's date rather than deciding it, because a
  /// billing date is a day on a calendar and only this side knows which
  /// day the person is looking at.
  func reload() {
    do {
      referenceDay = Self.today()
      primaryCurrency = Currencies.preferred
      allRenewals = try rondo.renewals(from: referenceDay, includeArchived: true)
      let everything = allRenewals
      renewals = everything.filter(navigation.matches)
      summaries = try Self.ordered(rondo.spendingSummary(on: referenceDay))
      categories = try rondo.categories()
      paymentMethods = try rondo.paymentMethods()
      newestRateDay = try rondo.newestRateDay()
      var readings: [String: RateReading] = [:]
      for code in currenciesInUse {
        readings[code] = try RateReading(
          pair: rondo.pairRate(currency: code, primary: primaryCurrency, on: referenceDay),
          isManual: rondo.rateInForce(currency: code, on: referenceDay)?.isManual ?? false
        )
      }
      rateReadings = readings
      ratesVersion &+= 1
      converted = convertedTotal(of: everything
        .filter { $0.subscription.status == .active }
        .map(\.subscription))

      // Archived rows are converted too: the table still shows what one
      // cost while it ran, and a row that stops showing both currencies
      // the day it is archived would look like a bug.
      var prices: [Uuid: DecimalString] = [:]
      for renewal in everything {
        let sub = renewal.subscription
        if let inPrimary = try rondo.convertAmount(
          amount: sub.amount,
          currency: sub.currency,
          to: Currencies.preferred,
          on: referenceDay
        ) {
          prices[sub.id] = inPrimary
        }
      }
      convertedPrices = prices

      // A count for every sidebar entry, including the categories nothing
      // is filed under: a category showing zero is how somebody sees there
      // is a place to file things, and hiding it would make the sidebar
      // rearrange itself every time a subscription changed hands.
      var tally: [Navigation: Int] = [
        .subscriptions: everything.count { $0.subscription.status == .active },
        .archived: everything.count { $0.subscription.status == .archived },
      ]
      for category in categories {
        tally[.category(category.id)] = everything.count {
          $0.subscription.status == .active && $0.subscription.categoryId == category.id
        }
      }
      counts = tally

      // Tomorrow, not today: the window is half-open, so a charge falling
      // today has to be inside it.
      let soon = (
        from: Self.day(after: referenceDay, days: 1),
        to: Self.day(after: referenceDay, days: 31)
      )
      next30Days = try rondo.windowTotals(from: soon.from, to: soon.to)
      // A forecast, so every charge takes today's rate: nothing is
      // published for next month, and pretending otherwise would be
      // inventing a number.
      next30DaysConverted = try rondo.convertedWindowTotal(
        from: soon.from,
        to: soon.to,
        primary: Currencies.preferred,
        on: referenceDay,
        forecast: true
      )

      // One call per subscription rather than one for all of them: there
      // are tens of these, and a call each keeps the core's answer per
      // subscription rather than assembling a ranking here.
      var spending: [(Subscription, SubscriptionTotal)] = []
      var byID: [Uuid: SubscriptionTotal] = [:]
      var convertedByID: [Uuid: DecimalString] = [:]
      // Archived rows are asked about too. They are left out of the
      // ranking, which is about what is being spent, but the table still
      // shows what one cost while it ran - that is the whole reason for
      // keeping an archived row rather than deleting it.
      for renewal in everything {
        let total = try rondo.subscriptionTotal(
          id: renewal.subscription.id,
          until: Self.day(after: referenceDay, days: 1)
        )
        guard total.chargeCount > 0 else { continue }
        byID[renewal.subscription.id] = total
        // The same window converted, charge by charge at the rate each fell
        // due under. A second call rather than converting `total` after the
        // fact, because converting a sum at one rate is a different figure
        // from summing amounts each converted at their own.
        let inPrimary = try rondo.convertedSubscriptionTotal(
          id: renewal.subscription.id,
          primary: Currencies.preferred,
          until: Self.day(after: referenceDay, days: 1),
          lockHistoricalRates: Self.locksHistoricalRates
        )
        // Only when every charge could be converted. A partial sum shown
        // beside a whole one would be a smaller number with nothing to say
        // it covers less.
        if inPrimary.convertedChargeCount == inPrimary.chargeCount {
          convertedByID[renewal.subscription.id] = inPrimary.total
        }
        if renewal.subscription.status == .active {
          spending.append((renewal.subscription, total))
        }
      }
      totals = byID
      convertedTotals = convertedByID
      // Sorted by the amount as a number, not as text: "9" is more than
      // "10" to a string comparison. Ranked on the billed amount, so the
      // ranking is the same whether or not rates have been fetched; the
      // figures beside the names are what carry the conversion.
      spending.sort {
        (Formatting.decimal($0.1.total) ?? 0) > (Formatting.decimal($1.1.total) ?? 0)
      }
      topSpending = spending.map { (subscription: $0.0, total: $0.1) }
    } catch {
      report(error)
    }
  }

  /// Records a subscription and refreshes what the window shows.
  ///
  /// Returns whether it was accepted: the core validates, so a rejected
  /// draft leaves the form open with the reason rather than closing over a
  /// value that was never stored.
  func add(_ draft: NewSubscription) -> Bool {
    do {
      _ = try rondo.addSubscription(draft: draft)
      reload()
      return true
    } catch {
      report(error)
      return false
    }
  }

  /// Saves an edited subscription.
  ///
  /// Returns whether the core accepted it, so a rejected change leaves the
  /// form open with the offending value rather than closing over an edit
  /// that was never stored.
  ///
  /// A changed price corrects the entry in force today rather than
  /// recording a rise; recording a real change of price is its own action.
  /// Today is read here rather than taken from `referenceDay`, which is
  /// only as fresh as the last reload - a write should land on the day it
  /// actually happens.
  func update(_ subscription: Subscription) -> Bool {
    do {
      _ = try rondo.updateSubscription(subscription: subscription, on: Self.today())
      reload()
      return true
    } catch {
      report(error)
      return false
    }
  }

  /// Stops counting a subscription, or starts again.
  ///
  /// Archiving is the answer for a service the person has left: the row
  /// and its history stay, and only the active list and the totals lose
  /// it. Deleting is for something entered by mistake.
  func setArchived(_ subscription: Subscription, _ archived: Bool) {
    do {
      _ = try rondo.setArchived(id: subscription.id, archived: archived, on: Self.today())
      reload()
    } catch {
      report(error)
    }
  }

  /// Removes a subscription for good.
  func delete(_ subscription: Subscription) {
    do {
      _ = try rondo.deleteSubscription(id: subscription.id)
      reload()
    } catch {
      report(error)
    }
  }

  /// The whole database as JSON, or nothing if it could not be read.
  ///
  /// Where it then goes is the window's business; the core only produces
  /// the text.
  func backupJSON() -> String? {
    do {
      return try rondo.exportBackup()
    } catch {
      report(error)
      return nil
    }
  }

  /// Merges a backup into the database and reports what it changed.
  ///
  /// Nothing is ever deleted: entries the file does not mention are left
  /// alone, so restoring the wrong file cannot destroy data. A failure
  /// part-way leaves the database exactly as it was, which is why this can
  /// return nothing without the caller having to undo anything.
  func restore(fromJSON json: String) -> ImportSummary? {
    do {
      let summary = try rondo.importBackup(json: json)
      reload()
      return summary
    } catch {
      report(error)
      return nil
    }
  }

  /// Totals with the person's primary currency first, the rest by code.
  ///
  /// Ordering only - the currencies stay apart and nothing is converted.
  /// Whichever one someone mostly pays in is the one they want to read
  /// without hunting for it.
  private static func ordered(_ summaries: [SpendingSummary]) -> [SpendingSummary] {
    let primary = Currencies.preferred
    return summaries.sorted { left, right in
      if (left.currency == primary) != (right.currency == primary) {
        return left.currency == primary
      }
      return left.currency < right.currency
    }
  }

  // Today in the person's own calendar, as `YYYY-MM-DD`.
  // -- exchange rates --

  /// The currencies a fetch has to ask for.
  ///
  /// Every currency something is billed in, **plus the one totals are
  /// shown in** - converting rupees into Hong Kong dollars needs a rate
  /// for both - and minus the base, which is never stored because it is 1
  /// against itself. Asking for all 200 to discard 190 would be slower for
  /// nothing.
  var currenciesToFetch: [String] {
    var codes = Set(allRenewals.map(\.subscription.currency))
    codes.insert(Currencies.preferred)
    codes.remove(baseCurrency())
    return codes.sorted()
  }

  /// The currencies the settings list shows a rate for.
  ///
  /// Deliberately *not* `currenciesToFetch`. Each row reads "1 X = n Y"
  /// against the primary currency, and the primary against itself is a row
  /// saying "1 HKD = 1 HKD" - which appeared on screen, with a status of
  /// "no rate" beside it, because one set was being used for both jobs.
  /// The base is excluded for the same reason it always was: there is
  /// nothing stored to show or to overrule.
  var currenciesInUse: [String] {
    var codes = Set(allRenewals.map(\.subscription.currency))
    codes.remove(Currencies.preferred)
    codes.remove(baseCurrency())
    return codes.sorted()
  }

  /// One amount in the primary currency at the rate in force on `day`.
  ///
  /// For amounts that are not a subscription's current price - a charge
  /// from two years ago, a cumulative total - where the day that matters
  /// is not today. Nothing comes back when no rate reaches that day, which
  /// the caller shows as the billed amount alone.
  func converted(_ amount: DecimalString, currency: String, on day: CivilDate) -> DecimalString? {
    // Reading these is what makes a view calling this redraw when rates
    // change; see `ratesVersion`. Deleting either line would compile, pass
    // every test, and quietly restore a bug that took three attempts to
    // find.
    _ = ratesVersion
    let primary = primaryCurrency
    return try? rondo.convertAmount(
      amount: amount,
      currency: currency,
      to: primary,
      on: day
    )
  }

  /// Every rate stored for one currency, earliest first.
  func rates(for currency: String) -> [ExchangeRate] {
    _ = ratesVersion
    return (try? rondo.rates(currency: currency)) ?? []
  }

  /// What a set of subscriptions comes to in the primary currency.
  ///
  /// Taken over whatever a window is showing, the same as `levelledTotal`:
  /// what has been narrowed to is the window's business, and adding the
  /// money is the core's. Nothing is summed on this side.
  ///
  /// Nothing comes back when the call fails, which a screen shows by
  /// falling back to the per-currency figures rather than by printing a
  /// zero that would read as "you spend nothing".
  func convertedTotal(of subscriptions: [Subscription]) -> ConvertedSpending? {
    try? rondo.convertedTotal(
      subscriptions: subscriptions,
      primary: Currencies.preferred,
      on: referenceDay
    )
  }

  /// Fetches whatever rates are missing and stores them.
  ///
  /// The span starts at the day after the newest rate already held, so a
  /// refresh asks only for what it does not have. With nothing held at
  /// all it starts at the earliest charge instead, which is the oldest day
  /// any total could need - fetching from today would leave every past
  /// charge unconvertible.
  ///
  /// Nothing here decides what a rate means or what it converts to. This
  /// is the frontend's whole share of the job: ask, and hand over.
  @MainActor
  func refreshRates() async {
    guard !isRefreshingRates else { return }
    let quotes = currenciesToFetch
    guard !quotes.isEmpty else {
      // Everything is already in the base currency, so there is nothing a
      // rate could be needed for. Not a failure, and not worth a request.
      rateFailure = nil
      rateNote = Self.word("Nothing to convert, so no rates are needed.")
      return
    }

    isRefreshingRates = true
    defer { isRefreshingRates = false }
    rateFailure = nil
    rateNote = nil

    let today = Self.today()
    // `earliestCharge` is doubly optional here: the call can fail, and it
    // answers with nothing when there are no charges at all. Both mean the
    // same thing to us, so both land on today.
    let beginning = ((try? rondo.earliestCharge(on: today)) ?? nil) ?? today

    // Where to resume from is asked *per currency*, not once. Asked once,
    // a currency that has never been fetched is skipped entirely whenever
    // any other currency already has today's rate - which is exactly what
    // happens the moment somebody changes the currency they total in, or
    // adds a subscription billed in a new one. The settings list filled
    // with empty rates that way and no amount of pressing Update fixed it.
    let start = quotes
      .map { code in
        rates(for: code).last.map { Self.day(after: $0.effectiveOn, days: 1) } ?? beginning
      }
      .min() ?? beginning

    guard start <= today else {
      // Already up to date. Nothing to ask for, and asking for a backwards
      // span would be an error rather than an empty answer - but saying so
      // is the whole point: this is the case that made the button look
      // broken, because pressing it did nothing anybody could see.
      rateNote = Self.word("Already up to date.")
      return
    }

    do {
      let fetched = try await RateSource.rates(from: start, to: today, quotes: quotes)
      let written = try rondo.recordRates(rates: fetched.map(\.stored))
      reload()
      rateNote = written > 0
        ? Self.word("Rates updated.")
        : Self.word("Already up to date.")
    } catch let failure as RateSource.Failure {
      rateFailure = Self.describe(failure)
    } catch {
      rateFailure = error.localizedDescription
    }
  }

  /// Whether a past charge is converted at the rate of its own day.
  ///
  /// Read from the defaults rather than held as a property, for the same
  /// reason `Currencies.preferred` is: the model is rebuilt from them on
  /// every reload, and a second copy could disagree with the switch.
  /// Absent means on, which is the answer that does not move.
  static var locksHistoricalRates: Bool {
    UserDefaults.standard.object(forKey: Preference.lockHistoricalRates) as? Bool ?? true
  }

  /// What one unit of `currency` buys of `primary` on `day`.
  ///
  /// The pair the settings row shows. Nothing when no rate reaches that
  /// day, which the row shows as an empty field rather than a zero.
  func pairRate(of currency: String, against primary: String, on day: CivilDate) -> DecimalString? {
    _ = ratesVersion
    return try? rondo.pairRate(currency: currency, primary: primary, on: day)
  }

  /// Stores a rate typed as a pair; returns why it could not be, or nothing.
  ///
  /// Returning the message rather than a bool because this one *can* fail
  /// for a reason worth reading: a pair between two currencies neither of
  /// which is the stored base needs the other side's rate, and somebody
  /// typing a rate by hand is often exactly the person who does not have
  /// it. A field that silently kept a value the core refused would be
  /// worse than one that says why.
  func setManualPairRate(
    of currency: String,
    against primary: String,
    on day: CivilDate,
    rate: DecimalString
  ) -> String? {
    do {
      _ = try rondo.setManualPairRate(from: currency, to: primary, on: day, rate: rate)
      reload()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  /// Records a rate somebody typed, which no later fetch will overwrite.
  ///
  /// Returns whether it was accepted; the core refuses anything that is
  /// not a positive number, and a field that silently keeps a bad value
  /// would be worse than one that says no.
  @discardableResult
  func setManualRate(currency: String, on day: CivilDate, rate: String) -> Bool {
    do {
      _ = try rondo.setManualRate(currency: currency, on: day, rate: rate)
      reload()
      return true
    } catch {
      rateFailure = error.localizedDescription
      return false
    }
  }

  /// Removes one stored rate.
  func deleteRate(currency: String, on day: CivilDate) {
    _ = try? rondo.deleteRate(currency: currency, on: day)
    reload()
  }

  /// One of the short outcomes a fetch reports, looked up.
  ///
  /// A `switch` rather than passing the text through, because the checks
  /// that keep the interface translated read literals in the source and
  /// cannot follow a string that was handed in.
  private static func word(_ outcome: String) -> String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch outcome {
    case "Rates updated.":
      String(localized: "Rates updated.", bundle: bundle, locale: locale,
             comment: "After a fetch that brought something back")
    case "Nothing to convert, so no rates are needed.":
      String(localized: "Nothing to convert, so no rates are needed.",
             bundle: bundle, locale: locale,
             comment: "After pressing update with everything already in one currency")
    default:
      String(localized: "Already up to date.", bundle: bundle, locale: locale,
             comment: "After a fetch that found nothing to ask for")
    }
  }

  /// What went wrong with a fetch, in words rather than a case name.
  private static func describe(_ failure: RateSource.Failure) -> String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch failure {
    case .unreachable:
      String(localized: "Could not reach the rate source. Check your connection and try again.",
             bundle: bundle, locale: locale,
             comment: "Rate fetch failed: offline or the host did not answer")
    case let .refused(status):
      String(localized: "The rate source answered with \(status).",
             bundle: bundle, locale: locale,
             comment: "Rate fetch failed: an HTTP status other than success")
    case .unreadable:
      String(localized: "The rate source sent something Rondo could not read.",
             bundle: bundle, locale: locale,
             comment: "Rate fetch failed: the answer was not the expected shape")
    }
  }

  static func today() -> CivilDate {
    Formatting.civilDate(from: Date())
  }

  /// A civil date `days` after another, in the person's own calendar.
  ///
  /// Through `Calendar` rather than by adding seconds, so a day that is not
  /// 24 hours long - the ones daylight saving shortens and lengthens -
  /// still counts as one day.
  static func day(after date: CivilDate, days: Int) -> CivilDate {
    guard let start = Formatting.parseCivilDate(date),
          let moved = Calendar.current.date(byAdding: .day, value: days, to: start)
    else { return date }
    return Formatting.civilDate(from: moved)
  }

  /// What a price on a cycle comes to in a month, or nothing when the
  /// amount is not yet a number.
  ///
  /// Asked while somebody is still typing, so a rejection here is ordinary
  /// rather than a failure worth reporting: an amount half entered is not
  /// an error, it is a person mid-sentence.
  ///
  /// Not called `levelledMonthly` after the core function it forwards to.
  /// The generated bindings compile into this same module, so a method of
  /// that name shadows the function it means to call and calls itself
  /// instead - which is a stack overflow, not a compile error, and the app
  /// dies the moment the form asks.
  func monthlyEquivalent(
    amount: String,
    currency: String,
    cycleCount: UInt32,
    cycleUnit: CycleUnit
  ) -> DecimalString? {
    try? levelledMonthly(
      amount: amount,
      currency: currency,
      cycleCount: cycleCount,
      cycleUnit: cycleUnit
    )
  }

  /// Records a way of paying, and hands back its id to select.
  ///
  /// Added at the end of the list rather than sorted by name: the order is
  /// the person's, and a card added today belongs where they put it. The
  /// id comes back so whoever asked for it can choose it straight away -
  /// nobody creates one of these except to use it.
  func addPaymentMethod(named name: String) -> Uuid? {
    do {
      let method = try rondo.addPaymentMethod(
        name: name,
        sortOrder: Int32(paymentMethods.count)
      )
      reload()
      return method.id
    } catch {
      report(error)
      return nil
    }
  }

  /// What a set of subscriptions comes to a month, per currency.
  ///
  /// Asked of the core rather than added up here. Which rows a window is
  /// showing is the window's own business - a page, a search, a filter -
  /// but adding their amounts is money arithmetic, and this side does none.
  ///
  /// Archived rows count for nothing, which the core decides: a total is
  /// about what is still being paid for.
  func levelledTotal(of subscriptions: [Subscription]) -> [SpendingSummary] {
    do {
      return try Self.ordered(rondo.levelledTotal(subscriptions: subscriptions))
    } catch {
      report(error)
      return []
    }
  }

  /// Removes a way of paying.
  ///
  /// The subscriptions that pointed at it are not deleted with it: the core
  /// detaches them, and they go back to saying nobody has said how they are
  /// paid for. That is the only sane reading - the subscription is still
  /// being charged either way.
  func deletePaymentMethod(_ method: PaymentMethod) {
    do {
      _ = try rondo.deletePaymentMethod(id: method.id)
      reload()
    } catch {
      report(error)
    }
  }

  /// Every price a subscription has been charged at, earliest first.
  ///
  /// Read on demand rather than kept: only the form and the detail screen
  /// want it, and holding every subscription's history would be a copy to
  /// keep true for the sake of two screens.
  func priceHistory(of id: Uuid) -> [Price] {
    do {
      return try rondo.priceHistory(subscriptionId: id)
    } catch {
      report(error)
      return []
    }
  }

  /// Every charge a subscription falls due for, earliest first.
  ///
  /// The half-open range the core takes, passed through unchanged: a caller
  /// wanting the next charge included asks for the day after it. Read on
  /// demand, like the price history, because only the detail screen wants
  /// it and there is no sense holding every subscription's.
  func charges(of subscription: Subscription, from: CivilDate, to: CivilDate) -> [Charge] {
    do {
      return try rondo.charges(id: subscription.id, from: from, to: to)
    } catch {
      report(error)
      return []
    }
  }

  /// Records that a subscription's price changed from a given day.
  ///
  /// A rise, not a correction: charges before that day keep what they cost.
  /// Correcting a price that was typed wrong is an ordinary edit.
  func recordPriceChange(of subscription: Subscription, amount: String, from: CivilDate) -> Bool {
    do {
      _ = try rondo.addPriceChange(
        subscriptionId: subscription.id,
        amount: amount,
        currency: subscription.currency,
        effectiveFrom: from
      )
      reload()
      return true
    } catch {
      report(error)
      return false
    }
  }

  /// Records a failure in the words the core used.
  ///
  /// The three `RondoError` cases differ in what the person can do about
  /// them, which later screens act on; for now the message is what matters.
  private func report(_ error: Error) {
    failure = (error as? RondoError)?.localizedDescription ?? error.localizedDescription
  }
}
