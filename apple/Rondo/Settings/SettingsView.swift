import SwiftUI

/// Where the app's own preferences live, reached with ⌘,.
///
/// Four tabs, the shape macOS uses for preferences. Anything that varies
/// per subscription belongs on the subscription and is not here: a reminder
/// lead time is the app's, a reminder is the subscription's.
struct SettingsView: View {
  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return TabView {
      GeneralSettings()
        .tabItem {
          tab(String(localized: "General", bundle: bundle, locale: locale,
                     comment: "Settings tab: appearance, language, and the like"),
              symbol: "gearshape")
        }
      ReminderSettings()
        .tabItem {
          tab(String(localized: "Reminders", bundle: bundle, locale: locale,
                     comment: "Settings tab: being told before a charge"),
              symbol: "bell")
        }
      DataSettings()
        .tabItem {
          tab(String(localized: "Data", bundle: bundle, locale: locale,
                     comment: "Settings tab: where the database is, and backups"),
              symbol: "externaldrive")
        }
      AboutSettings()
        .tabItem {
          tab(String(localized: "About", bundle: bundle, locale: locale,
                     comment: "Settings tab: what this app is"),
              symbol: "info.circle")
        }
    }
    .frame(width: 600)
    .scenePadding()
  }

  /// One tab's label, built from words already looked up.
  ///
  /// `Label(_:systemImage:)` takes a key, and a key is resolved against the
  /// system's language rather than the chosen one.
  private func tab(_ title: String, symbol: String) -> some View {
    Label {
      Text(verbatim: title)
    } icon: {
      Image(systemName: symbol)
    }
  }
}
