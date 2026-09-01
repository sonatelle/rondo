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
      Section {
        identity
          .frame(maxWidth: .infinity)
          .padding(.vertical, Theme.Space.m)
      }

      Section("Links") {
        AboutLink(
          "Source",
          systemImage: "curlybraces",
          tint: .navAll,
          to: "https://github.com/sonatelle/rondo"
        )
        AboutLink(
          "Releases",
          systemImage: "shippingbox",
          tint: .navAnalytics,
          to: "https://github.com/sonatelle/rondo/releases"
        )
        AboutLink(
          "Report an issue",
          systemImage: "ladybug",
          tint: .categoryStorage,
          to: "https://github.com/sonatelle/rondo/issues"
        )
      }

      Section {
        Text("© 2026 Sonatelle · aliaxy · MIT License")
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textFaint)
          .frame(maxWidth: .infinity)
      }
    }
    .formStyle(.grouped)
  }

  private var identity: some View {
    VStack(spacing: Theme.Space.xs) {
      // The app's own icon, read from the bundle rather than drawn again,
      // so it cannot drift from what the Dock shows.
      if let icon = NSImage(named: "AppIcon") {
        Image(nsImage: icon)
          .resizable()
          .frame(width: 72, height: 72)
          .padding(.bottom, Theme.Space.xs)
      }
      Text("Rondo")
        .font(.system(size: 17, weight: .semibold))
      Text(Self.version)
        .font(Theme.Font.caption)
        .foregroundStyle(Color.textMuted)
        .monospacedDigit()
      Text("A theme that keeps returning — and so does every subscription.")
        .font(Theme.Font.caption)
        .foregroundStyle(Color.textMuted)
        .multilineTextAlignment(.center)
        .padding(.top, Theme.Space.s)
      Text("Everything stays in one file on this Mac. No cloud, no account, no network.")
        .font(Theme.Font.footnote)
        .foregroundStyle(Color.textFaint)
        .multilineTextAlignment(.center)
    }
  }

  /// Read from the bundle rather than written here, so it cannot disagree
  /// with what was actually built and released.
  private static var version: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "—"
    let build = info?["CFBundleVersion"] as? String ?? "—"
    return "Version \(short) (\(build))"
  }
}

/// A row that leaves the app, marked as such.
///
/// The icons are tinted, the way the design tints the settings tabs and
/// the sidebar: colour here marks what a row is, not how urgent it is.
/// They are deliberately drawn from the cool end of the palette, because
/// red and amber mean "this is charged soon" everywhere else in Rondo and
/// spending them on a link would make that quieter.
private struct AboutLink: View {
  /// A key, not a `String`: `Text(someString)` shows the text as written
  /// and never looks it up, so these rows stayed English.
  let title: LocalizedStringKey
  let systemImage: String
  let tint: Color
  let destination: URL

  init(_ title: LocalizedStringKey, systemImage: String, tint: Color, to address: String) {
    self.title = title
    self.systemImage = systemImage
    self.tint = tint
    // The addresses are literals in this file, so a typo is a row that
    // goes to the project rather than a crash.
    destination = URL(string: address) ?? URL(string: "https://github.com/sonatelle/rondo")!
  }

  var body: some View {
    Link(destination: destination) {
      HStack(spacing: Theme.Space.m) {
        // A column of a fixed width rather than a `Label`, which sizes
        // each icon to itself: the code symbol is half again as wide as a
        // circle, so the titles beside them started at different places.
        Image(systemName: systemImage)
          .foregroundStyle(tint)
          .frame(width: 18)
        Text(title)
        Spacer()
        Image(systemName: "arrow.up.right")
          .font(.caption)
          .foregroundStyle(Color.textFaint)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
