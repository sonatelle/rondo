import SwiftUI

/// Where the app's own preferences live, reached with ⌘,.
///
/// Four tabs, the shape macOS uses for preferences. Anything that varies
/// per subscription belongs on the subscription and is not here: a reminder
/// lead time is the app's, a reminder is the subscription's.
struct SettingsView: View {
  var body: some View {
    TabView {
      GeneralSettings()
        .tabItem { Label("General", systemImage: "gearshape") }
      ReminderSettings()
        .tabItem { Label("Reminders", systemImage: "bell") }
      DataSettings()
        .tabItem { Label("Data", systemImage: "externaldrive") }
      AboutSettings()
        .tabItem { Label("About", systemImage: "info.circle") }
    }
    .frame(width: 600)
    .scenePadding()
  }
}
