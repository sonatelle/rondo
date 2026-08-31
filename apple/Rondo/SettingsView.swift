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

private struct GeneralSettings: View {
  @AppStorage(Preference.appearance) private var appearance = Appearance.system
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
      ? "Off, closing the window leaves Rondo in the menu bar and out of the Dock."
      : "With no menu bar item, closing the window quits either way."
  }
}

/// Empty until reminders exist.
///
/// The tab is here because the design has it and because the next piece of
/// work fills it; an empty tab that says so is more honest than a tab that
/// appears later and makes the settings window rearrange itself.
private struct ReminderSettings: View {
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

private struct DataSettings: View {
  @State private var location = (try? Database.fileURL())?.path(percentEncoded: false) ?? ""

  var body: some View {
    Form {
      LabeledContent("Database") {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
          // Selectable so the path can be copied into a terminal or a
          // backup script, which is the only reason to show it at all.
          Text(location)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(3)
            .truncationMode(.middle)
          Button("Show in Finder") {
            guard let url = try? Database.fileURL() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
          }
        }
      }
      Text(
        """
        Rondo keeps everything in this one file and never sends it anywhere. \
        Copy it, and its -wal and -shm companions, to keep a backup.
        """
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      Section {
        Text("Export a backup or restore one from the File menu.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Restoring merges and never deletes, so opening the wrong file cannot cost you data.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}

private struct AboutSettings: View {
  var body: some View {
    Form {
      LabeledContent("Version", value: Self.version)
      Text(
        """
        Rondo is a subscription tracker. Everything it knows stays in one \
        file on this Mac: no cloud, no account, and no network requests of \
        any kind.
        """
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      Link("Source and releases", destination: URL(string: "https://github.com/sonatelle/rondo")!)
    }
    .formStyle(.grouped)
  }

  /// Read from the bundle rather than written here, so it cannot disagree
  /// with what was actually built and released.
  private static var version: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "—"
    let build = info?["CFBundleVersion"] as? String ?? "—"
    return "\(short) (\(build))"
  }
}
