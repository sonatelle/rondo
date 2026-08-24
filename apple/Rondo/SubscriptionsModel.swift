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

  /// Subscriptions with the date each is next charged, soonest first.
  private(set) var renewals: [Renewal] = []

  /// Spending totals, one entry per currency.
  private(set) var summaries: [SpendingSummary] = []

  /// Whether anything is hidden behind the archived filter.
  ///
  /// Without this the empty list would claim there are no subscriptions
  /// while some are merely archived, which is not the same thing and
  /// leaves the person with no hint that the filter is what to change.
  private(set) var hasArchived = false

  /// The last failure, for the interface to show and the person to dismiss.
  var failure: String?

  /// Whether archived subscriptions appear in the list.
  ///
  /// Without a way to see them, archiving would be indistinguishable from
  /// deleting: the promise it makes is that the record is still there.
  var showsArchived = false {
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
      renewals = try rondo.renewals(from: Self.today(), includeArchived: showsArchived)
      summaries = try rondo.spendingSummary()
      hasArchived = try rondo.subscriptions(includeArchived: true)
        .contains { $0.status == .archived }
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
