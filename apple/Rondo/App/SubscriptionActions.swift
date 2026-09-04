import SwiftUI

/// What the menus can do to whatever the front window has selected.
///
/// The menu bar is built once, outside any window, so it cannot reach into
/// a window's state directly. The window publishes this instead, and a
/// command is `nil` when it does not apply - which is how the menu knows
/// to grey itself out rather than offering something that would do nothing.
struct SubscriptionActions {
  var add: () -> Void
  var edit: (() -> Void)?
  var archive: (() -> Void)?
  var restore: (() -> Void)?
  var delete: (() -> Void)?
}

extension FocusedValues {
  @Entry var subscriptionActions: SubscriptionActions?
}

/// The app's menu bar.
///
/// Every item here is also reachable from the table's context menu. Both
/// call the same closures so the two cannot come to disagree about when an
/// action applies.
struct SubscriptionCommands: Commands {
  @FocusedValue(\.subscriptionActions) private var actions
  @FocusedValue(\.backupActions) private var backup

  var body: some Commands {
    // Replaces the "New Item" Xcode puts in the File menu by default.
    CommandGroup(replacing: .newItem) {
      Button(String(localized: "New Subscription", bundle: Localization.bundle,
                    locale: Localization.locale,
                    comment: "File menu command")) { actions?.add() }
        .keyboardShortcut("n")
        .disabled(actions == nil)
    }

    CommandGroup(after: .newItem) {
      Divider()
      Button(String(localized: "Edit Subscription…", bundle: Localization.bundle,
                    locale: Localization.locale,
                    comment: "File menu command")) { actions?.edit?() }
        .keyboardShortcut("e")
        .disabled(actions?.edit == nil)
    }

    // The group macOS reserves in the File menu for moving data in and
    // out, which is where someone looking for a backup will look first.
    CommandGroup(replacing: .importExport) {
      Button(String(localized: "Export Backup…", bundle: Localization.bundle,
                    locale: Localization.locale,
                    comment: "File menu command")) { backup?.export() }
        .disabled(backup == nil)
      Button(String(localized: "Restore from Backup…", bundle: Localization.bundle,
                    locale: Localization.locale,
                    comment: "File menu command")) { backup?.restore() }
        .disabled(backup == nil)
    }

    // A menu of its own, because these are the verbs particular to this
    // app rather than things every app does to a document.
    CommandMenu(String(localized: "Subscription", bundle: Localization.bundle,
                       locale: Localization.locale,
                       comment: "Name of the app's own menu"))
    {
      Button(String(localized: "Archive", bundle: Localization.bundle,
                    locale: Localization.locale,
                    comment: "Subscription menu command")) { actions?.archive?() }
        .disabled(actions?.archive == nil)
      Button(String(localized: "Restore", bundle: Localization.bundle,
                    locale: Localization.locale,
                    comment: "Subscription menu command: un-archive")) { actions?.restore?() }
        .disabled(actions?.restore == nil)
      Divider()
      Button(String(localized: "Delete…", bundle: Localization.bundle,
                    locale: Localization.locale,
                    comment: "Subscription menu command")) { actions?.delete?() }
        .keyboardShortcut(.delete, modifiers: [])
        .disabled(actions?.delete == nil)
    }
  }
}
