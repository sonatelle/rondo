import Foundation
import Observation
import UserNotifications

/// Which subscription a notification asked to be opened.
///
/// A notification arrives while the app may be closed, and what it wants
/// done belongs to a window that does not exist yet. So the delegate puts
/// the id here and the window picks it up when there is one, rather than
/// reaching into a view from a callback that runs before any view does.
@Observable
@MainActor
final class ReminderRoute {
  static let shared = ReminderRoute()

  /// The subscription to open, cleared once a window has done so.
  var wanted: Uuid?

  private init() {}
}

/// What was pressed on a reminder, as plain values.
///
/// A `UNNotificationResponse` is not `Sendable`, and the delegate that
/// receives one does not run on the main actor - so what is needed is read
/// off it there and only this crosses the line. Outside `ReminderActions`
/// because that is main-actor bound, and even building a value of a type
/// nested in it would have to wait its turn.
struct ReminderPress: Sendable {
  /// The key the charge day travels under, so a reminder put off by a day
  /// can say how many are left rather than repeating what it said before.
  ///
  /// Here rather than on `Reminders`, which is main-actor bound: the
  /// delegate reads them from a callback that is not, and even a constant
  /// on an isolated type has to wait its turn.
  static let chargeDayKey = "chargeDay"
  /// The key the subscription's name travels under, for the same reason.
  static let nameKey = "name"

  let action: String
  let identifier: String
  /// Kept as it was written, so a reminder put off by a day still says the
  /// date and amount it said the first time.
  let subtitle: String
  /// The day the charge falls, and the subscription's name. Absent on
  /// anything not scheduled by this build.
  let chargeDay: String?
  let name: String?
}

/// What the buttons on a reminder do.
///
/// Two, as the design draws them. Opening is what clicking the body does
/// anyway, so the button earns its place only by landing on the
/// subscription rather than on whatever page was last open.
@MainActor
enum ReminderActions {
  /// The category every charge reminder is filed under. Registered once
  /// at launch: macOS matches a delivered notification to its category by
  /// this string, and a notification whose category was never registered
  /// arrives with no buttons at all.
  static let category = "charge"
  static let view = "charge.view"
  static let snooze = "charge.snooze"

  /// How long "remind me later" puts it off.
  ///
  /// A day, not an hour. These are charges days away, and the question
  /// this button answers is "not now, tell me tomorrow" - an hour later
  /// would arrive in the same sitting it was dismissed from.
  static let snoozeDays = 1

  /// Registers the category and its buttons.
  static func register(delegate: UNUserNotificationCenterDelegate) {
    let bundle = Localization.bundle
    let locale = Localization.locale
    let centre = UNUserNotificationCenter.current()
    centre.delegate = delegate
    centre.setNotificationCategories([
      UNNotificationCategory(
        identifier: category,
        actions: [
          UNNotificationAction(
            identifier: view,
            title: String(localized: "View", bundle: bundle, locale: locale,
                          comment: "Reminder button: opens the subscription"),
            options: [.foreground]
          ),
          UNNotificationAction(
            identifier: snooze,
            title: String(localized: "Remind me tomorrow", bundle: bundle, locale: locale,
                          comment: "Reminder button: puts it off by a day"),
            options: []
          ),
        ],
        intentIdentifiers: []
      ),
    ])
  }

  /// Acts on whichever button was pressed.
  static func handle(_ press: ReminderPress) {
    switch press.action {
    case snooze:
      snooze(press)
    case view, UNNotificationDefaultActionIdentifier:
      // The body counts as View: somebody who clicked the notification
      // itself wants the same thing as somebody who pressed the button.
      ReminderRoute.shared.wanted = subscriptionID(of: press.identifier)
    default:
      break
    }
  }

  /// Schedules the same reminder again a day later, counting down again.
  ///
  /// The title is rewritten rather than reused. "Charged in 2 days" is
  /// true on the day it was written for and wrong on the next one, so
  /// carrying it forward unchanged would have the notification lie by
  /// exactly the amount it was put off by.
  ///
  /// Nothing is scheduled when the charge would already have landed:
  /// telling somebody tomorrow about a payment taken today is worse than
  /// saying nothing.
  private static func snooze(_ press: ReminderPress) {
    let calendar = Calendar.current
    guard let later = calendar.date(byAdding: .day, value: snoozeDays, to: Date()),
          let day = press.chargeDay,
          let charge = Formatting.parseCivilDate(day),
          let name = press.name,
          let left = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: later),
            to: calendar.startOfDay(for: charge)
          ).day,
          left > 0
    else { return }

    let content = UNMutableNotificationContent()
    content.title = Reminders.title(name: name, days: left)
    content.subtitle = press.subtitle
    content.sound = .default
    content.categoryIdentifier = category
    content.userInfo = [ReminderPress.chargeDayKey: day, ReminderPress.nameKey: name]
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: later)
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(
        identifier: press.identifier,
        content: content,
        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
      )
    )
  }

  /// The subscription a reminder is about, from its own identifier.
  ///
  /// Read back out of the id rather than carried in `userInfo`: the id is
  /// already built from it, and two places holding the same fact is two
  /// places for them to disagree.
  private static func subscriptionID(of identifier: String) -> Uuid? {
    let prefix = "charge-"
    guard identifier.hasPrefix(prefix) else { return nil }
    return String(identifier.dropFirst(prefix.count))
  }
}
