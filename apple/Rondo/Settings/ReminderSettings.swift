import SwiftUI

/// Empty until reminders exist.
///
/// The tab is here because the design has it and because the next piece of
/// work fills it; an empty tab that says so is more honest than a tab that
/// appears later and makes the settings window rearrange itself.
struct ReminderSettings: View {
  var body: some View {
    Form {
      ContentUnavailableView {
        Label {
          Text(verbatim: String(localized: "No reminders yet", bundle: Localization.bundle,
                                locale: Localization.locale,
                                comment: "The reminders tab, which is empty until they exist"))
        } icon: {
          Image(systemName: "bell.slash")
        }
      } description: {
        Text(verbatim: String(
          localized: "Rondo will be able to tell you before a charge lands. It cannot yet.",
          bundle: Localization.bundle, locale: Localization.locale,
          comment: "Under the empty reminders tab"
        ))
      }
    }
    .formStyle(.grouped)
  }
}
