import SwiftUI

struct GeneralSettings: View {
  @AppStorage(Preference.appearance) private var appearance = Appearance.system
  @AppStorage(Preference.appLanguage) private var appLanguage = ""
  @AppStorage(Preference.showsMenuBarItem) private var showsMenuBarItem = true
  @AppStorage(Preference.quitsOnWindowClose) private var quitsOnWindowClose = false
  @AppStorage(Preference.primaryCurrency) private var primaryCurrency = ""
  @AppStorage(Preference.firstWeekday) private var firstWeekday = 2

  /// Read from the system rather than stored, so it cannot disagree with
  /// what System Settings shows.
  @State private var launchesAtLogin = LaunchAtLogin.isEnabled

  /// Why the system refused to change the login item, when it did.
  @State private var launchFailure: String?

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return Form {
      Section {
        Toggle(String(localized: "Open Rondo at login", bundle: bundle, locale: locale,
                      comment: "Setting: start the app when the Mac is logged into"),
               isOn: launchBinding)
        if let launchFailure {
          Text(launchFailure)
            .font(.caption)
            .foregroundStyle(Color.danger)
        }

        Toggle(String(localized: "Show Rondo in the menu bar", bundle: bundle, locale: locale,
                      comment: "Setting: keep the status item"),
               isOn: $showsMenuBarItem)
        Text(verbatim: String(localized: "Glance at the next charges without opening a window.",
                              bundle: bundle, locale: locale,
                              comment: "Under the menu bar setting"))
          .font(.caption)
          .foregroundStyle(.secondary)

        Toggle(String(localized: "Quit when the window closes", bundle: bundle, locale: locale,
                      comment: "Setting: what closing the last window means"),
               isOn: $quitsOnWindowClose)
        Text(verbatim: closingExplanation)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        Picker(String(localized: "Language", bundle: bundle, locale: locale,
                      comment: "Setting: which language the interface is in"),
               selection: $appLanguage)
        {
          Text(verbatim: String(localized: "Follow the system", bundle: bundle, locale: locale,
                                comment: "Take this setting from the Mac's own")).tag("")
          Divider()
          // Offered from the bundle rather than from a list here, so a
          // language added to the catalogue turns up without any Swift
          // being touched.
          ForEach(Localization.available, id: \.self) { code in
            Text(verbatim: Localization.displayName(of: code)).tag(code)
          }
        }

        Picker(String(localized: "Appearance", bundle: bundle, locale: locale,
                      comment: "Setting: light, dark, or the Mac's own"),
               selection: $appearance)
        {
          ForEach(Appearance.allCases) { choice in
            Text(verbatim: choice.title).tag(choice)
          }
        }
        .pickerStyle(.segmented)
        .onChange(of: appearance) { _, chosen in
          chosen.apply()
        }

        Picker(String(localized: "Primary currency", bundle: bundle, locale: locale,
                      comment: "Setting: the currency a new subscription starts in"),
               selection: $primaryCurrency)
        {
          Text(verbatim: String(localized: "Follow the system", bundle: bundle, locale: locale,
                                comment: "Take this setting from the Mac's own")).tag("")
          Divider()
          ForEach(Currencies.all, id: \.self) { code in
            Text(verbatim: code).tag(code)
          }
        }
        Text(verbatim: String(
          localized: "Where a new subscription starts, and which total is listed first. Rondo never converts between currencies.",
          bundle: bundle, locale: locale, comment: "Under the primary currency setting"
        ))
        .font(.caption)
        .foregroundStyle(.secondary)

        Picker(String(localized: "Weeks start on", bundle: bundle, locale: locale,
                      comment: "Setting: which day a calendar week begins on"),
               selection: $firstWeekday)
        {
          Text(verbatim: String(localized: "Monday", bundle: bundle, locale: locale,
                                comment: "Day a week starts on")).tag(2)
          Text(verbatim: String(localized: "Sunday", bundle: bundle, locale: locale,
                                comment: "Day a week starts on")).tag(1)
          Text(verbatim: String(localized: "Saturday", bundle: bundle, locale: locale,
                                comment: "Day a week starts on")).tag(7)
        }
        Text(verbatim: String(localized: "Sets how the calendar is laid out.",
                              bundle: bundle, locale: locale,
                              comment: "Under the week start setting"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  /// Turning this on asks the system, which can refuse; the toggle only
  /// moves if it agreed. A switch that flips back with no explanation is
  /// worse than one that says what happened.
  private var launchBinding: Binding<Bool> {
    Binding(
      get: { launchesAtLogin },
      set: { wanted in
        do {
          try LaunchAtLogin.set(wanted)
          launchesAtLogin = LaunchAtLogin.isEnabled
          launchFailure = nil
        } catch {
          launchesAtLogin = LaunchAtLogin.isEnabled
          launchFailure = error.localizedDescription
        }
      }
    )
  }

  /// Closing the window quits anyway when there is no menu bar item, since
  /// otherwise Rondo would keep running with nothing left to click.
  private var closingExplanation: String {
    showsMenuBarItem
      ? String(
        localized: "Off, closing the window leaves Rondo in the menu bar and out of the Dock.",
        bundle: Localization.bundle,
        locale: Localization.locale
      )
      : String(
        localized: "With no menu bar item, closing the window quits either way.",
        bundle: Localization.bundle,
        locale: Localization.locale
      )
  }
}
