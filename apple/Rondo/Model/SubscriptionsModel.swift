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
  private(set) var summaries: [SpendingSummary] = []

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

  /// What actually falls due in the next thirty days, per currency.
  ///
  /// Charged rather than levelled: this card answers "what will leave my
  /// account", and a yearly plan that renews next week is the whole of it
  /// rather than a twelfth.
  private(set) var next30Days: [WindowTotal] = []

  /// What each subscription has cost since its first charge, most first.
  ///
  /// Cumulative, at the prices each charge was made at - which is what the
  /// price history exists for. A subscription that has not been charged yet
  /// is left out: nothing has been spent on it to rank.
  private(set) var topSpending: [(subscription: Subscription, total: SubscriptionTotal)] = []

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
      allRenewals = try rondo.renewals(from: referenceDay, includeArchived: true)
      let everything = allRenewals
      renewals = everything.filter(navigation.matches)
      summaries = try Self.ordered(rondo.spendingSummary(on: referenceDay))
      categories = try rondo.categories()

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
      next30Days = try rondo.windowTotals(
        from: Self.day(after: referenceDay, days: 1),
        to: Self.day(after: referenceDay, days: 31)
      )

      // One call per subscription rather than one for all of them: there
      // are tens of these, and a call each keeps the core's answer per
      // subscription rather than assembling a ranking here.
      var spending: [(Subscription, SubscriptionTotal)] = []
      for renewal in everything where renewal.subscription.status == .active {
        let total = try rondo.subscriptionTotal(
          id: renewal.subscription.id,
          until: Self.day(after: referenceDay, days: 1)
        )
        if total.chargeCount > 0 {
          spending.append((renewal.subscription, total))
        }
      }
      // Sorted by the amount as a number, not as text: "9" is more than
      // "10" to a string comparison. Currencies are never converted, so a
      // ranking across them is a rough one and the amount beside each name
      // is what says so.
      spending.sort {
        (Formatting.decimal($0.1.total) ?? 0) > (Formatting.decimal($1.1.total) ?? 0)
      }
      topSpending = spending.map { (subscription: $0.0, total: $0.1) }
    } catch {
      report(error)
    }
  }

  /// Reorders the rows for a table column the person clicked.
  ///
  /// Sorting is a property of the view, but the array it sorts lives here,
  /// so the reorder has to be asked for rather than done in place.
  func sort(using order: [KeyPathComparator<Renewal>]) {
    renewals.sort(using: order)
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

  /// Today in the person's own calendar, as `YYYY-MM-DD`.
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

  /// Records a failure in the words the core used.
  ///
  /// The three `RondoError` cases differ in what the person can do about
  /// them, which later screens act on; for now the message is what matters.
  private func report(_ error: Error) {
    failure = (error as? RondoError)?.localizedDescription ?? error.localizedDescription
  }
}
