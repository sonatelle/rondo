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

  /// The last failure, for the interface to show and the person to dismiss.
  var failure: String?

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
      renewals = try rondo.renewals(from: Self.today(), includeArchived: false)
      summaries = try rondo.spendingSummary()
    } catch {
      report(error)
    }
  }

  /// Today in the person's own calendar, as `YYYY-MM-DD`.
  static func today() -> CivilDate {
    let now = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    return String(format: "%04d-%02d-%02d", now.year ?? 0, now.month ?? 0, now.day ?? 0)
  }

  /// Records a failure in the words the core used.
  ///
  /// The three `RondoError` cases differ in what the person can do about
  /// them, which later screens act on; for now the message is what matters.
  private func report(_ error: Error) {
    failure = (error as? RondoError)?.localizedDescription ?? error.localizedDescription
  }
}
