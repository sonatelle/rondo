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
    Form {
      Section {
        Toggle("Open Rondo at login", isOn: launchBinding)
        if let launchFailure {
          Text(launchFailure)
            .font(.caption)
            .foregroundStyle(Color.danger)
        }

        Toggle("Show Rondo in the menu bar", isOn: $showsMenuBarItem)
        Text("Glance at the next charges without opening a window.")
          .font(.caption)
          .foregroundStyle(.secondary)

        Toggle("Quit when the window closes", isOn: $quitsOnWindowClose)
        Text(closingExplanation)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        Picker("Language", selection: $appLanguage) {
          Text("Follow the system").tag("")
          Divider()
          // Offered from the bundle rather than from a list here, so a
          // language added to the catalogue turns up without any Swift
          // being touched.
          ForEach(Localization.available, id: \.self) { code in
            Text(verbatim: Localization.displayName(of: code)).tag(code)
          }
        }

        Picker("Appearance", selection: $appearance) {
          ForEach(Appearance.allCases) { choice in
            Text(choice.title).tag(choice)
          }
        }
        .pickerStyle(.segmented)
        .onChange(of: appearance) { _, chosen in
          chosen.apply()
        }

        Picker("Primary currency", selection: $primaryCurrency) {
          Text("Follow the system").tag("")
          Divider()
          ForEach(Currencies.all, id: \.self) { code in
            Text(code).tag(code)
          }
        }
        Text("Where a new subscription starts, and which total is listed first. Rondo never converts between currencies.")
          .font(.caption)
          .foregroundStyle(.secondary)

        Picker("Weeks start on", selection: $firstWeekday) {
          Text("Monday").tag(2)
          Text("Sunday").tag(1)
          Text("Saturday").tag(7)
        }
        Text("Sets how the calendar is laid out.")
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
