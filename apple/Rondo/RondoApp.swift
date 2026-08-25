import SwiftUI

@main
struct RondoApp: App {
  /// Names the main window so the status item can bring it back after it
  /// has been closed.
  static let mainWindowID = "main"

  /// Opening the database can fail, and the app has to say so rather than
  /// launching into a window that silently shows nothing.
  private let launch: Result<SubscriptionsModel, Error>

  init() {
    launch = Result { try SubscriptionsModel.opening() }
  }

  var body: some Scene {
    Window("Rondo", id: Self.mainWindowID) {
      switch launch {
      case let .success(model):
        ContentView(model: model)
      case let .failure(error):
        UnavailableView(error: error)
      }
    }
    .defaultSize(width: 720, height: 460)
    .commands { SubscriptionCommands() }

    // A glance at what is coming, without a window. It shows nothing when
    // the database could not be opened: the main window is where that
    // failure is explained, and a status item has no room to explain it.
    MenuBarExtra {
      if case let .success(model) = launch {
        MenuBarView(model: model)
      }
    } label: {
      Label("Rondo", systemImage: "repeat")
    }
    .menuBarExtraStyle(.window)
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
