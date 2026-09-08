import SwiftUI

/// What hangs off the status item: the next few charges, and the total.
///
/// This is the view for a glance, not for managing. It answers "what is
/// coming and when" without a window, and hands anything else over to the
/// main one.
struct MenuBarView: View {
  let model: SubscriptionsModel
  @Environment(\.openWindow) private var openWindow

  /// Puts the status item's window away.
  ///
  /// SwiftUI's own dismissal rather than closing the panel by hand.
  /// Closing the key window does make it disappear, but the status item
  /// goes on looking pressed: whether the item is showing its window is
  /// state SwiftUI keeps, and reaching around it leaves the two disagreeing.
  @Environment(\.dismiss) private var dismissPanel

  /// How many charges fit before the list stops being a glance.
  ///
  /// Three, and a count for the rest. The number is deliberately small:
  /// past a handful this is a list to read rather than a thing to glance
  /// at, and the window is where reading happens.
  private static let visible = 3

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      upcomingSection
      Divider()
      totalsSection
      Divider()
      actions
    }
    .frame(width: 300)
    .background(Color.surface)
  }

  private var upcomingSection: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(alignment: .leading, spacing: 0) {
      Text(verbatim: String(localized: "Up next", bundle: bundle, locale: locale,
                            comment: "Menu bar heading over the next few charges"))
        .font(Theme.Font.footnote)
        .kerning(0.46)
        .foregroundStyle(Color.textMuted)
        .padding(.bottom, Theme.Space.m)

      if upcoming.isEmpty {
        Text(verbatim: String(localized: "Nothing scheduled", bundle: bundle, locale: locale,
                              comment: "Nothing is charged in the period being shown"))
          .font(Theme.Font.body)
          .foregroundStyle(Color.textMuted)
          .padding(.vertical, Theme.Space.s)
      } else {
        ForEach(upcoming) { renewal in
          UpcomingRow(
            renewal: renewal,
            today: model.referenceDay,
            primaryCurrency: model.primaryCurrency,
            converted: model.convertedPrices[renewal.subscription.id]
          )
        }
        if remaining > 0 {
          Text(verbatim: String(localized: "and \(remaining) more", bundle: bundle,
                                locale: locale,
                                comment: "How many charges the menu bar did not list"))
            .font(Theme.Font.footnote)
            .foregroundStyle(Color.textFaint)
            .padding(.top, Theme.Space.s)
        }
      }
    }
    .padding(.horizontal, Theme.Space.card)
    .padding(.top, Theme.Space.xxl)
    .padding(.bottom, Theme.Space.l)
  }

  private var totalsSection: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(verbatim: String(localized: "A month", bundle: Localization.bundle,
                            locale: Localization.locale,
                            comment: "Menu bar: what everything comes to monthly"))
        .font(Theme.Font.caption)
        .foregroundStyle(Color.textMuted)
      Spacer(minLength: Theme.Space.m)
      VStack(alignment: .trailing, spacing: 1) {
        if let converted = model.converted, converted.subscriptionCount > 0 {
          HStack(spacing: Theme.Space.xs) {
            // The status item has no room to explain an omission, so it
            // marks one and leaves the explanation to the window.
            if !converted.unconverted.isEmpty {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.danger)
            }
            Text(verbatim: Formatting.amount(converted.monthly, currency: converted.currency))
              .monospacedDigit()
          }
        } else if model.summaries.isEmpty {
          // A placeholder, not prose: it would otherwise sit in the
          // catalogue as an em dash waiting to be translated.
          Text(verbatim: "—").foregroundStyle(Color.textFaint)
        } else {
          ForEach(model.summaries, id: \.currency) { summary in
            Text(verbatim: Formatting.amount(summary.monthly, currency: summary.currency))
              .monospacedDigit()
          }
        }
      }
      .font(Theme.Font.label)
      .foregroundStyle(Color.textPrimary)
    }
    .padding(.horizontal, Theme.Space.card)
    .padding(.vertical, Theme.Space.l)
  }

  private var actions: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(alignment: .leading, spacing: 1) {
      MenuBarButton(String(localized: "Open Rondo", bundle: bundle, locale: locale,
                           comment: "Menu bar: brings the main window back"),
                    symbol: "creditcard")
      {
        // This window first. Opening the main window makes it key, and a
        // status item's window that has lost key stays on screen with
        // nothing dismissing it - which left it hanging over the window it
        // had just opened.
        dismissPanel()
        // Back into the Dock before the window appears: the delegate drops
        // Rondo out of it when the last window closes, and coming back
        // without this leaves a window belonging to an app with no icon.
        NSApp.setActivationPolicy(.regular)
        openWindow(id: RondoApp.mainWindowID)
        raiseWindow()
      }
      SettingsRow(
        title: String(localized: "Settings…", bundle: bundle, locale: locale,
                      comment: "Menu bar: opens the settings window"),
        dismissPanel: dismissPanel
      )
      // Grouped as a menu groups: what opens something, then what ends
      // the session. A rule between them is how every other app says it.
      Divider()
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.xs)
      MenuBarButton(String(localized: "Quit Rondo", bundle: bundle, locale: locale,
                           comment: "Menu bar: quits the app"),
                    symbol: "xmark.square", shortcut: .init(modifiers: "⌘", key: "Q", equivalent: "q", modifierKeys: .command))
      {
        NSApp.terminate(nil)
      }
    }
    .padding(.horizontal, Theme.Space.m)
    .padding(.vertical, Theme.Space.s)
  }

  /// Brings the window that was just asked for to the front, and puts the
  /// keyboard in it.
  ///
  /// On the next turn of the runloop, because the window does not exist
  /// yet when the button that asked for it returns. Activating before it
  /// does is what left the keyboard in the menu bar: an application made
  /// active with no window able to take key hands focus to the menu bar,
  /// and the first menu lights up as though somebody had pressed for it.
  private func raiseWindow() {
    DispatchQueue.main.async {
      NSApp.activate()
      NSApp.windows
        .first { $0.canBecomeKey && $0.isVisible }?
        .makeKeyAndOrderFront(nil)
    }
  }

  /// The soonest few charges, whatever the window happens to be showing.
  private var upcoming: [Renewal] {
    Array(model.upcoming.prefix(Self.visible))
  }

  private var remaining: Int {
    model.upcoming.count - upcoming.count
  }
}

/// One charge: what, how much, and how soon.
private struct UpcomingRow: View {
  let renewal: Renewal
  let today: CivilDate
  /// The currency the total below this list is in.
  let primaryCurrency: String
  /// This charge in that currency, when a rate reaches it.
  let converted: DecimalString?

  var body: some View {
    HStack(spacing: Theme.Space.l) {
      ServiceMark(name: renewal.subscription.name)
      Text(renewal.subscription.name)
        .font(Theme.Font.body)
        .foregroundStyle(Color.textPrimary)
        .lineLimit(1)
      Spacer(minLength: Theme.Space.m)
      VStack(alignment: .trailing, spacing: 1) {
        // The converted figure only, where every other screen shows the
        // billed currency under it. This popover is a glance and the design
        // gives the row two lines, one of which the urgency needs; a third
        // would make three rows of it. Left as it was, though, the row said
        // "₹700.00" directly above a total saying "¥273.15" with nothing
        // joining them, and a foreign amount alone tells somebody counting
        // in yuan nothing about whether it is large. What is billed is one
        // click away in the window.
        Text(verbatim: Formatting.amount(
          renewal.subscription.amount,
          currency: renewal.subscription.currency,
          convertedTo: primaryCurrency,
          converted: converted
        ).primary)
          .font(Theme.Font.label)
          .foregroundStyle(Color.textPrimary)
          .monospacedDigit()
          .lineLimit(1)

        // The one place a glance carries colour: how soon this lands.
        Text(Formatting.relative(renewal.date, from: today))
          .font(.system(size: 11.5, weight: urgency == .distant ? .regular : .semibold))
          .foregroundStyle(urgency.foreground)
      }
    }
    .padding(.vertical, Theme.Space.s)
  }

  private var urgency: Urgency {
    Urgency.of(renewal.date, from: today)
  }
}

/// A row in the bottom group, which behaves like a menu item without being
/// one - `MenuBarExtra(.window)` gives a window, so these are buttons.
private struct MenuBarButton: View {
  /// Already through the catalogue, like every other word in the app: a
  /// key would be resolved against the system's language rather than the
  /// chosen one.
  let title: String

  /// The glyph in the leading column.
  ///
  /// A real menu of macOS's own carries no icons - the app menu in any
  /// application shows that - but a window hanging off a status item is
  /// not that menu, and the ones people compare this to do carry them.
  /// Thin, grey and small: a column to glance down, not a row of buttons.
  let symbol: String

  /// The shortcut, written out on the trailing edge.
  ///
  /// Bound as well as shown. It used to be shown only, on the grounds
  /// that "the main menu handles these whether this window is open or
  /// not" - which is untrue for most of this window's life: with no main
  /// window open the app is an accessory, has no menu bar at all, and
  /// pressing the keys printed here did nothing.
  ///
  /// Held in two parts rather than as one string, so they can be set in
  /// two columns; see the body for why that matters.
  var shortcut: Shortcut?

  /// A shortcut, split where it has to be to line up down a list.
  struct Shortcut {
    /// Everything held down, as glyphs: "⌘", "⇧⌘".
    let modifiers: String
    /// The one key pressed, as it is drawn: "Q", ",".
    let key: String
    /// The same key as SwiftUI binds it. Given rather than derived from
    /// `key`, which is a label: "Q" is drawn upper case and pressed lower.
    let equivalent: KeyEquivalent
    /// What is held down, as SwiftUI binds it.
    let modifierKeys: EventModifiers
  }

  let action: () -> Void

  @State private var isHovering = false

  init(
    _ title: String,
    symbol: String,
    shortcut: Shortcut? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.symbol = symbol
    self.shortcut = shortcut
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      MenuBarRowLabel(title: title, symbol: symbol, shortcut: shortcut, isHovering: isHovering)
    }
    .buttonStyle(.plain)
    .modifier(BoundShortcut(shortcut: shortcut))
    .onHover { isHovering = $0 }
  }
}

/// How a row in this window looks.
///
/// Apart from the button so that `SettingsLink` can wear the same face:
/// opening settings is the one row that must not be an ordinary button,
/// and it would otherwise have to draw itself a second time.
private struct MenuBarRowLabel: View {
  let title: String
  let symbol: String
  let shortcut: MenuBarButton.Shortcut?
  let isHovering: Bool

  var body: some View {
    HStack(spacing: Theme.Space.m) {
      Image(systemName: symbol)
        .font(.system(size: 12))
        .foregroundStyle(Color.textPrimary)
        // A fixed column, so the words beside them line up however wide
        // each glyph happens to be.
        .frame(width: 16)
      Text(verbatim: title)
        .font(Theme.Font.body)
        .foregroundStyle(Color.textPrimary)
      Spacer(minLength: Theme.Space.m)
      if let shortcut {
        // Two columns rather than one string, so the modifier lines up
        // down the list. Set as one right-aligned run, "⌘ ," and "⌘ Q"
        // put their modifiers at different places, because a comma is
        // narrower than a Q. A real menu does not have this problem -
        // `NSMenu` is given the key and the modifier mask separately and
        // lays them out itself - but this popover is a window rather
        // than a menu, which is what buys it amounts and colour, so the
        // columns are arranged here by hand.
        HStack(spacing: 4) {
          Text(verbatim: shortcut.modifiers)
          Text(verbatim: shortcut.key)
            // Wide enough for the widest key here, so a narrow one does
            // not pull the modifier along with it.
            .frame(width: 11, alignment: .leading)
        }
        .font(Theme.Font.footnote)
        .monospacedDigit()
        .foregroundStyle(Color.textFaint)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Theme.Space.m)
    .padding(.vertical, Theme.Space.s)
    .background(
      RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        .fill(isHovering ? Color.sidebarHover : .clear)
    )
    .contentShape(Rectangle())
  }
}

/// Binds a row's printed shortcut, when it has one.
///
/// A modifier rather than an `if` around `.keyboardShortcut`, because that
/// would give the button two different types and SwiftUI would rebuild it
/// as a different view whenever the shortcut appeared or went away.
private struct BoundShortcut: ViewModifier {
  let shortcut: MenuBarButton.Shortcut?

  func body(content: Content) -> some View {
    if let shortcut {
      content.keyboardShortcut(shortcut.equivalent, modifiers: shortcut.modifierKeys)
    } else {
      content
    }
  }
}

/// The row that opens settings.
///
/// A view of its own for one reason: it is a `SettingsLink` rather than a
/// button, and so it has to carry the hover state that `MenuBarButton`
/// keeps for every other row. Lifted out of that button without this, the
/// row was handed a constant `false` and stopped lighting up under the
/// pointer.
///
/// `SettingsLink` rather than an action, because what this did before was
/// send `showSettingsWindow:` down the responder chain - a private
/// selector, aimed at a chain with no target once this panel closes. The
/// window came up behind everything and arrived only when something else
/// activated the app, and deferring the send by a turn stopped it arriving
/// at all. This is the API meant for the job, and it does not care which
/// window is key.
private struct SettingsRow: View {
  let title: String
  let dismissPanel: DismissAction

  @State private var isHovering = false

  var body: some View {
    SettingsLink {
      MenuBarRowLabel(
        title: title,
        symbol: "gearshape",
        shortcut: .init(modifiers: "⌘", key: ",", equivalent: ",", modifierKeys: .command),
        isHovering: isHovering
      )
    }
    .buttonStyle(.plain)
    .keyboardShortcut(",", modifiers: .command)
    .onHover { isHovering = $0 }
    // The link opens the window; these are the things around it that still
    // have to happen - dropping the panel, and coming back into the Dock so
    // the window belongs to an app with an icon.
    .simultaneousGesture(TapGesture().onEnded {
      dismissPanel()
      NSApp.setActivationPolicy(.regular)
      NSApp.activate()
    })
  }
}
