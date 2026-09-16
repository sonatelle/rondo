import Foundation
import UserNotifications

/// Telling somebody before a charge lands.
///
/// The whole point of the app is not being surprised by an automatic
/// payment, and a tracker you have to remember to open does not do that.
/// This is the one piece that works when Rondo is closed.
///
/// Every request is scheduled against the person's own calendar day, the
/// same as every other date here: a charge falls on a date, not at an
/// instant, and a reminder for it should arrive on the morning of a day
/// they recognise.
@MainActor
enum Reminders {
  /// How many requests are scheduled at once.
  ///
  /// macOS keeps at most 64 pending per app and silently drops the rest,
  /// so the soonest are scheduled and the remainder wait: every reload
  /// schedules again, and a charge three months out will have its turn
  /// long before it arrives. Below 64 to leave room for the summary and
  /// for anything added later.
  static let limit = 48

  /// Whether the person has been asked, and what they said.
  static func authorization() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  /// Asks for permission, returning whether it was given.
  ///
  /// Called only from the switch in Settings, never at launch. A
  /// permission dialog on first run is the one people dismiss without
  /// reading, and macOS remembers a refusal: the cost of asking at the
  /// wrong moment is paid once and cannot be taken back from inside the
  /// app. Asked when somebody turns reminders on, it is an answer to
  /// something they just did.
  static func requestAuthorization() async -> Bool {
    (try? await UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .sound])) ?? false
  }

  /// Puts the pending reminders back in step with the data, if they are
  /// wanted at all.
  ///
  /// Takes the values rather than the model: it is called from a reload
  /// that does not run on the main actor, and handing an object across
  /// that line is what Swift's concurrency checking is for. Renewals and
  /// amounts are plain values and travel safely.
  static func refresh(
    renewals: [Renewal],
    primaryCurrency: String,
    converted: [Uuid: DecimalString]
  ) async {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: Preference.remindersOn) else {
      cancelAll()
      return
    }
    await reschedule(
      renewals,
      leadHour: defaults.object(forKey: Preference.reminderHour) as? Int ?? 9,
      leadMinute: defaults.object(forKey: Preference.reminderMinute) as? Int ?? 0,
      primaryCurrency: primaryCurrency,
      converted: converted
    )
  }

  /// Replaces every pending reminder with ones for these renewals.
  ///
  /// Cancel-and-rebuild rather than working out the difference. The
  /// difference is more code and has a worse failure: a request left
  /// behind for a subscription that was deleted still fires, and tells
  /// somebody about a charge that is not coming.
  ///
  /// A subscription whose reminder day has already passed is skipped.
  /// `UNCalendarNotificationTrigger` would not fire for it anyway, and a
  /// reminder about a charge that is already due says nothing the app
  /// does not show the moment it opens.
  static func reschedule(
    _ renewals: [Renewal],
    leadHour: Int,
    leadMinute: Int,
    primaryCurrency: String,
    converted: [Uuid: DecimalString]
  ) async {
    let centre = UNUserNotificationCenter.current()
    centre.removeAllPendingNotificationRequests()
    guard await authorization() == .authorized else { return }

    let calendar = Calendar.current
    let now = Date()
    let due = renewals
      .filter { $0.subscription.status == .active && $0.subscription.reminderLeadDays > 0 }
      .compactMap { renewal -> (Renewal, DateComponents)? in
        guard let charge = Formatting.parseCivilDate(renewal.date),
              let day = calendar.date(
                byAdding: .day,
                value: -Int(renewal.subscription.reminderLeadDays),
                to: charge
              )
        else { return nil }
        var when = calendar.dateComponents([.year, .month, .day], from: day)
        when.hour = leadHour
        when.minute = leadMinute
        guard let fires = calendar.date(from: when), fires > now else { return nil }
        return (renewal, when)
      }
      .sorted { left, right in left.0.date < right.0.date }
      .prefix(limit)

    for (renewal, when) in due {
      let content = UNMutableNotificationContent()
      content.title = title(
        name: renewal.subscription.name,
        days: Int(renewal.subscription.reminderLeadDays)
      )
      content.subtitle = subtitle(
        for: renewal,
        primaryCurrency: primaryCurrency,
        converted: converted[renewal.subscription.id]
      )
      content.sound = .default
      content.categoryIdentifier = ReminderActions.category
      // The day and the name travel with the request so that putting the
      // reminder off by a day can say how many are left. Neither can be
      // worked back out of the notification itself.
      content.userInfo = [
        ReminderPress.chargeDayKey: renewal.date,
        ReminderPress.nameKey: renewal.subscription.name,
      ]
      let request = UNNotificationRequest(
        // The subscription's own id, so rescheduling replaces rather than
        // duplicates even if a cancel were ever to fail.
        identifier: "charge-\(renewal.subscription.id)",
        content: content,
        trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
      )
      try? await centre.add(request)
    }
  }

  /// Drops every pending reminder, for when they are switched off.
  static func cancelAll() {
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
  }

  /// "iCloud+ is charged in 2 days".
  ///
  /// The name first, because a notification is read in a stack of them
  /// and the name is what tells somebody whether this one is theirs to
  /// act on.
  ///
  /// A countdown rather than a date, which is what the design writes -
  /// and the reason the day has to travel with the request: a countdown
  /// is only true on the day it was written for.
  static func title(name: String, days: Int) -> String {
    String(localized: "\(name) is charged in \(days) days",
           bundle: Localization.bundle, locale: Localization.locale,
           comment: "Reminder title: what is about to be charged and how soon")
  }

  /// "2 March · ¥21.00 · Monthly" - the three things that decide whether
  /// it is worth opening the app about.
  private static func subtitle(
    for renewal: Renewal,
    primaryCurrency: String,
    converted: DecimalString?
  ) -> String {
    let amount = Formatting.amount(
      renewal.subscription.amount,
      currency: renewal.subscription.currency,
      convertedTo: primaryCurrency,
      converted: converted
    )
    return [
      Formatting.date(renewal.date),
      amount.primary,
      renewal.cycleDescription,
    ].joined(separator: " · ")
  }
}
