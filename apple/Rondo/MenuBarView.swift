import SwiftUI

/// What hangs off the status item: the next few charges, and the total.
///
/// This is the view for a glance, not for managing. It answers "what is
/// coming and when" without a window, and hands anything else over to the
/// main one.
struct MenuBarView: View {
  let model: SubscriptionsModel
  @Environment(\.openWindow) private var openWindow

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
    VStack(alignment: .leading, spacing: 0) {
      Text("Up next")
        .font(Theme.Font.footnote)
        .kerning(0.46)
        .foregroundStyle(Color.textMuted)
        .padding(.bottom, Theme.Space.m)

      if upcoming.isEmpty {
        Text("Nothing scheduled")
          .font(Theme.Font.body)
          .foregroundStyle(Color.textMuted)
          .padding(.vertical, Theme.Space.s)
      } else {
        ForEach(upcoming) { renewal in
          UpcomingRow(renewal: renewal, today: model.referenceDay)
        }
        if remaining > 0 {
          Text("and \(remaining) more")
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
      Text("A month")
        .font(Theme.Font.caption)
        .foregroundStyle(Color.textMuted)
      Spacer(minLength: Theme.Space.m)
      VStack(alignment: .trailing, spacing: 1) {
        if model.summaries.isEmpty {
          // A placeholder, not prose: it would otherwise sit in the
          // catalogue as an em dash waiting to be translated.
          Text(verbatim: "—").foregroundStyle(Color.textFaint)
        } else {
          ForEach(model.summaries, id: \.currency) { summary in
            Text(Formatting.amount(summary.monthly, currency: summary.currency))
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
    VStack(alignment: .leading, spacing: 1) {
      MenuBarButton("Open Rondo") {
        // Back into the Dock before the window appears: the delegate drops
        // Rondo out of it when the last window closes, and coming back
        // without this leaves a window belonging to an app with no icon.
        NSApp.setActivationPolicy(.regular)
        openWindow(id: RondoApp.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
      }
      MenuBarButton("Quit Rondo", tint: Color.textTertiary) {
        NSApp.terminate(nil)
      }
    }
    .padding(.horizontal, Theme.Space.m)
    .padding(.vertical, Theme.Space.s)
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

  var body: some View {
    HStack(spacing: Theme.Space.l) {
      ServiceMark(name: renewal.subscription.name)
      Text(renewal.subscription.name)
        .font(Theme.Font.body)
        .foregroundStyle(Color.textPrimary)
        .lineLimit(1)
      Spacer(minLength: Theme.Space.m)
      VStack(alignment: .trailing, spacing: 1) {
        Text(
          Formatting.amount(
            renewal.subscription.amount,
            currency: renewal.subscription.currency
          )
        )
        .font(Theme.Font.label)
        .foregroundStyle(Color.textPrimary)
        .monospacedDigit()

        // The one place a glance carries colour: how soon this lands.
        Text(Formatting.relative(renewal.date))
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
  /// A key, not a `String`: `Text(someString)` is the verbatim initialiser,
  /// which shows the text as written and never looks it up.
  let title: LocalizedStringKey
  var tint: Color = .textPrimary
  let action: () -> Void

  @State private var isHovering = false

  init(_ title: LocalizedStringKey, tint: Color = .textPrimary, action: @escaping () -> Void) {
    self.title = title
    self.tint = tint
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(Theme.Font.body)
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(
          RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .fill(isHovering ? Color.sidebarHover : .clear)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }
}
