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

  /// How many subscriptions each sidebar entry would show.
  ///
  /// Shown as counts beside the filters, and it is what lets an empty list
  /// say whether there is nothing at all or only nothing active.
  private(set) var counts: [SubscriptionFilter: Int] = [:]

  /// The last failure, for the interface to show and the person to dismiss.
  var failure: String?

  /// Which subscriptions the window is showing.
  var filter: SubscriptionFilter = .active {
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
      allRenewals = try rondo.renewals(from: Self.today(), includeArchived: true)
      let everything = allRenewals
      renewals = everything.filter(filter.matches)
      summaries = try rondo.spendingSummary()
      counts = [
        .active: everything.count { $0.subscription.status == .active },
        .archived: everything.count { $0.subscription.status == .archived },
        .all: everything.count,
      ]
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
  func update(_ subscription: Subscription) -> Bool {
    do {
      _ = try rondo.updateSubscription(subscription: subscription)
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
      _ = try rondo.setArchived(id: subscription.id, archived: archived)
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

  /// Today in the person's own calendar, as `YYYY-MM-DD`.
  static func today() -> CivilDate {
    Formatting.civilDate(from: Date())
  }

  /// Records a failure in the words the core used.
  ///
  /// The three `RondoError` cases differ in what the person can do about
  /// them, which later screens act on; for now the message is what matters.
  private func report(_ error: Error) {
    failure = (error as? RondoError)?.localizedDescription ?? error.localizedDescription
  }
}
