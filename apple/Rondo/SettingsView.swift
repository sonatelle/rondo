import SwiftUI

/// Where the app's own preferences live, reached with ⌘,.
///
/// Deliberately small. Most of what a subscription tracker could offer as
/// a setting belongs to a subscription instead - a reminder is per
/// subscription, not per app - so this holds only what is true of the app
/// as a whole.
struct SettingsView: View {
  var body: some View {
    TabView {
      GeneralSettings()
        .tabItem { Label("General", systemImage: "gear") }
      DataSettings()
        .tabItem { Label("Data", systemImage: "externaldrive") }
    }
    .frame(width: 420)
    .scenePadding()
  }
}

private struct GeneralSettings: View {
  /// Whether the app keeps running once its window is closed.
  ///
  /// Off by default: the status item is the reason to stay, and an app
  /// that refuses to quit when you close its window is a surprise the
  /// person should opt into.
  @AppStorage(RondoApp.staysInMenuBarKey) private var staysInMenuBar = false

  var body: some View {
    Form {
      Toggle("Keep Rondo in the menu bar after closing the window", isOn: $staysInMenuBar)
      Text("The menu bar item stays either way while Rondo is running.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
  }
}

private struct DataSettings: View {
  @State private var location = (try? Database.fileURL())?.path(percentEncoded: false) ?? ""

  var body: some View {
    Form {
      LabeledContent("Database") {
        VStack(alignment: .leading, spacing: 6) {
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
    }
    .formStyle(.grouped)
  }
}
