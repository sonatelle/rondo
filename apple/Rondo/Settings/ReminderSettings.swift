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
        Label("No reminders yet", systemImage: "bell.slash")
      } description: {
        Text("Rondo will be able to tell you before a charge lands. It cannot yet.")
      }
    }
    .formStyle(.grouped)
  }
}
