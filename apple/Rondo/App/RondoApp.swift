import SwiftUI

/// Decides what closing the last window means.
///
/// SwiftUI has no scene-level equivalent, so this is the one place an
/// AppKit delegate is needed. Preferences are read on each call rather than
/// cached, so a toggle takes effect without a restart.
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Applies the stored appearance before any window is on screen, so the
  /// first one does not appear in the wrong one and then correct itself.
  func applicationDidFinishLaunching(_: Notification) {
    let stored = UserDefaults.standard.string(forKey: Preference.appearance) ?? ""
    (Appearance(rawValue: stored) ?? .system).apply()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
    let defaults = UserDefaults.standard
    let quits = defaults.bool(forKey: Preference.quitsOnWindowClose)
    let hasMenuBarItem = defaults.object(forKey: Preference.showsMenuBarItem) as? Bool ?? true

    // Closing the window normally leaves Rondo running in the menu bar and
    // drops it from the Dock, which is the shape of a thing you glance at.
    // But with no menu bar item there would be nothing left to click: the
    // app would be running, invisible, and reachable only through Force
    // Quit. So the absence of that item makes closing the window quit.
    guard !quits, hasMenuBarItem else {
      return true
    }
    NSApp.setActivationPolicy(.accessory)
    return false
  }
}

@main
struct RondoApp: App {
  /// Names the main window so the status item can bring it back after it
  /// has been closed.
  static let mainWindowID = "main"

  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  @AppStorage(Preference.showsMenuBarItem) private var showsMenuBarItem = true

  /// The chosen language, used below rather than only declared: SwiftUI
  /// rebuilds on what a body actually reads.
  @AppStorage(Preference.appLanguage) private var appLanguage = ""

  /// Opening the database can fail, and the app has to say so rather than
  /// launching into a window that silently shows nothing.
  private let launch: Result<SubscriptionsModel, Error>

  init() {
    launch = Result { try SubscriptionsModel.opening() }
  }

  var body: some Scene {
    Window("Rondo", id: Self.mainWindowID) {
      Group {
        switch launch {
        case let .success(model):
          ContentView(model: model)
        case let .failure(error):
          UnavailableView(error: error)
        }
      }
      // Back into the Dock whenever a window is on screen; the delegate
      // takes it out again when the last one closes.
      .onAppear { NSApp.setActivationPolicy(.regular) }
      .environment(\.locale, Localization.locale(for: appLanguage))
      // Rebuilt rather than merely re-supplied. Handing the scene a new
      // locale is not enough on its own: text already on screen keeps the
      // words it resolved, and only a language change forced through the
      // identity redraws it. Tried without this and the window stayed in
      // the old language until the next launch.
      //
      // The cost is the view state that lives in the tree - which row is
      // selected, which column sorts. Changing language is rare enough to
      // pay that, and the data is safe either way: the model outlives the
      // views. Moving that state into the model would make the rebuild
      // free, and the overview rewrite is going to move it there anyway.
      .id(appLanguage)
      // A floor, so the layouts have one narrow case to be right about
      // rather than every width there is. See `RondoWindow` for where the
      // number comes from.
      .frame(
        minWidth: RondoWindow.minimumWidth,
        minHeight: RondoWindow.minimumHeight
      )
    }
    .defaultSize(width: 1080, height: 760)
    .commands { SubscriptionCommands() }

    // A glance at what is coming, without a window. It shows nothing when
    // the database could not be opened: the main window is where that
    // failure is explained, and a status item has no room to explain it.
    MenuBarExtra(isInserted: $showsMenuBarItem) {
      if case let .success(model) = launch {
        MenuBarView(model: model)
          .environment(\.locale, Localization.locale(for: appLanguage))
          .id(appLanguage)
      }
    } label: {
      // The card from the middle of the app's own mark. Not the ring that
      // surrounds it there: a circling arrow in a menu bar reads as a
      // refresh control, and this item refreshes nothing - it lists what
      // is charged next.
      Label("Rondo", systemImage: "creditcard")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environment(\.locale, Localization.locale(for: appLanguage))
        .id(appLanguage)
    }
  }
}

/// Shown when the database could not be opened at all.
///
/// There is nothing useful to display in that state and no action the app
/// can take on the person's behalf, so it says plainly what happened and
/// where the file it wanted is.
private struct UnavailableView: View {
  let error: Error

  var body: some View {
    ContentUnavailableView {
      Label("Rondo cannot open its database", systemImage: "exclamationmark.triangle")
    } description: {
      Text(error.localizedDescription)
    } actions: {
      if let url = try? Database.fileURL() {
        Button("Show in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([url])
        }
      }
    }
    .padding()
  }
}
