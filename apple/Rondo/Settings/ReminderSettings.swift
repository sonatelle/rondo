import SwiftUI
import UserNotifications

/// Whether Rondo tells you before a charge lands, and when.
///
/// Only two controls, and deliberately. How many days of warning is a
/// property of each subscription - one you would cancel needs longer than
/// one you would not - and it is set on the subscription itself. Repeating
/// it here as a global would either be ignored or would overwrite what is
/// already stored per row.
struct ReminderSettings: View {
  /// The open database, or nothing when it could not be opened. Without
  /// one there is nothing to schedule, but the switch and the refusal
  /// notice still tell the truth.
  let model: SubscriptionsModel?

  @AppStorage(Preference.remindersOn) private var remindersOn = false
  @AppStorage(Preference.reminderHour) private var hour = 9
  @AppStorage(Preference.reminderMinute) private var minute = 0

  /// What macOS says about notifications for this app, re-read whenever
  /// the window appears: it can be changed in System Settings while Rondo
  /// is running, and a switch describing a permission it no longer has is
  /// a switch that quietly does nothing.
  @State private var authorization: UNAuthorizationStatus = .notDetermined
  @State private var isAsking = false

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    Form {
      Section {
        Toggle(isOn: Binding(get: { remindersOn }, set: { turn(on: $0) })) {
          Text(verbatim: String(localized: "Remind me before a charge",
                                bundle: bundle, locale: locale,
                                comment: "The reminders switch"))
          Text(verbatim: String(
            localized: "Each subscription says how many days of warning it wants.",
            bundle: bundle, locale: locale,
            comment: "Under the reminders switch: where the lead time is set"
          ))
        }
        .disabled(isAsking || authorization == .denied)

        if remindersOn, authorization == .authorized {
          DatePicker(
            selection: Binding(get: { timeOfDay }, set: { set(timeOfDay: $0) }),
            displayedComponents: .hourAndMinute
          ) {
            Text(verbatim: String(localized: "Arrive at", bundle: bundle, locale: locale,
                                  comment: "What time of day reminders are delivered"))
          }
        }
      }

      // Said plainly rather than left to a switch that will not move.
      // macOS remembers a refusal, and nothing in an app can undo it -
      // so the only useful thing to do is say where it can be undone.
      if authorization == .denied {
        Section {
          LabeledContent {
            Button(String(localized: "Open System Settings", bundle: bundle, locale: locale,
                          comment: "Opens the notifications pane"))
            {
              openNotificationSettings()
            }
          } label: {
            Text(verbatim: String(localized: "Notifications are turned off for Rondo",
                                  bundle: bundle, locale: locale,
                                  comment: "When macOS has been told not to allow them"))
            Text(verbatim: String(
              localized: "macOS keeps this choice. It can only be changed there.",
              bundle: bundle, locale: locale,
              comment: "Under the refused-notifications row"
            ))
          }
        }
      }
    }
    .formStyle(.grouped)
    .task {
      authorization = await Reminders.authorization()
      // A permission taken away outside the app leaves the switch on and
      // nothing arriving. Put it back so the two agree.
      if authorization != .authorized, remindersOn {
        remindersOn = false
      }
    }
  }

  private var timeOfDay: Date {
    Calendar.current.date(
      from: DateComponents(hour: hour, minute: minute)
    ) ?? Date()
  }

  private func set(timeOfDay: Date) {
    let parts = Calendar.current.dateComponents([.hour, .minute], from: timeOfDay)
    hour = parts.hour ?? 9
    minute = parts.minute ?? 0
    let model = model
    Task { await model?.rescheduleReminders() }
  }

  /// Turning it on asks macOS the first time, and only then.
  private func turn(on wanted: Bool) {
    guard wanted else {
      remindersOn = false
      Reminders.cancelAll()
      return
    }
    isAsking = true
    Task {
      if authorization == .notDetermined {
        _ = await Reminders.requestAuthorization()
      }
      authorization = await Reminders.authorization()
      remindersOn = authorization == .authorized
      isAsking = false
      await model?.rescheduleReminders()
    }
  }

  private func openNotificationSettings() {
    guard let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.notifications"
    ) else { return }
    NSWorkspace.shared.open(url)
  }
}
