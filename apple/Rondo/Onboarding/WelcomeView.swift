import SwiftUI

/// What a brand new database shows before it shows an empty table.
///
/// The design draws this as a window of its own. It is a sheet instead,
/// deliberately: both of its buttons act on the main window - one opens the
/// form, the other the file picker - and a second window would have to
/// reach across into the first to do either. A sheet also cannot be lost.
/// A welcome window can be sent behind the main one by a single click,
/// leaving somebody looking at an empty app with no idea what became of the
/// thing that was explaining it.
struct WelcomeView: View {
  /// Opens the form on the window underneath.
  let add: () -> Void

  /// Opens the file picker, for somebody who has used Rondo before.
  let restore: () -> Void

  /// Closes without doing either.
  let later: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      heading
      points
        .padding(.top, 30)
      buttons
        .padding(.top, 26)
    }
    .padding(.horizontal, 40)
    .padding(.top, Theme.Space.window)
    .padding(.bottom, 28)
    // The design's width, and fixed: this is a page of prose, and prose
    // set across a window somebody has dragged wide is unreadable.
    .frame(width: 600)
    .background(Color.surface)
  }

  /// The mark, what Rondo is for, and the two things somebody wants to know
  /// before letting an app near their money.
  private var heading: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(alignment: .leading, spacing: 0) {
      // The real icon rather than the design's lettered placeholder. It is
      // the same mark that will be in the Dock a moment from now, which is
      // the whole job of an icon on a screen like this.
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .frame(width: 60, height: 60)
      Text(verbatim: String(localized: "Never be surprised by an automatic payment",
                            bundle: bundle, locale: locale,
                            comment: "First-run screen: the headline"))
        .font(Theme.Font.windowTitle)
        .tracking(-0.7)
        .foregroundStyle(Color.textPrimary)
        .padding(.top, 18)
      Text(verbatim: String(
        localized: "Rondo keeps track of when each subscription is charged and how much, and tells you before it happens. Everything stays on this Mac, and there is no account to make.",
        bundle: bundle, locale: locale,
        comment: "First-run screen: what the app does"
      ))
      .font(Theme.Font.intro)
      .lineSpacing(5)
      .foregroundStyle(Color.textTertiary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, Theme.Space.m)
    }
  }

  /// Three reasons, in the order somebody would ask for them: what it does
  /// for me, what it shows me, and what it does with my data.
  private var points: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(alignment: .leading, spacing: Theme.Space.xxl) {
      point(
        symbol: "calendar",
        colour: .categoryRed,
        title: String(localized: "Told in advance", bundle: bundle, locale: locale,
                      comment: "First-run screen: the reminders"),
        detail: String(localized: "A notice a few days before the charge, while there is still time to cancel",
                       bundle: bundle, locale: locale,
                       comment: "First-run screen: under the reminders")
      )
      point(
        symbol: "chart.bar.fill",
        colour: .categoryGreen,
        title: String(localized: "See what it adds up to", bundle: bundle, locale: locale,
                      comment: "First-run screen: the totals"),
        detail: String(localized: "Levelled by month and totalled per subscription, with other currencies converted into your main one",
                       bundle: bundle, locale: locale,
                       comment: "First-run screen: under the totals")
      )
      point(
        symbol: "externaldrive.fill",
        colour: .categoryCyan,
        title: String(localized: "Stays on this Mac", bundle: bundle, locale: locale,
                      comment: "First-run screen: where the data lives"),
        detail: String(localized: "A local database you can export; restoring a backup merges and never deletes",
                       bundle: bundle, locale: locale,
                       comment: "First-run screen: under where the data lives")
      )
    }
  }

  /// One reason: a coloured mark, what it is, and a line saying what that
  /// means in practice.
  private func point(
    symbol: String,
    colour: Color,
    title: String,
    detail: String
  ) -> some View {
    HStack(alignment: .top, spacing: Theme.Space.xxl) {
      Image(systemName: symbol)
        .font(.system(size: 18))
        .foregroundStyle(colour)
        // A fixed box, so three symbols of different widths still leave
        // their three sentences starting on the same line down the page.
        .frame(width: 22, height: 22)
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: title)
          .font(Theme.Font.sectionTitle)
          .foregroundStyle(Color.textPrimary)
        Text(verbatim: detail)
          .font(Theme.Font.label)
          .foregroundStyle(Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// The three ways out, in the order they are likely to be wanted.
  ///
  /// "Maybe later" is set apart on the right and drawn faintly, as the
  /// design has it: it is the one that does nothing, and it should not
  /// compete with the two that do.
  private var buttons: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return HStack(spacing: Theme.Space.xl) {
      BrandButton(
        title: String(localized: "Add your first subscription", bundle: bundle, locale: locale,
                      comment: "First-run screen: opens the form"),
        height: 32,
        sidePadding: 18,
        action: add
      )
      // The system's own bordered button, which is already the white-on-
      // shadow the design draws beside a filled one.
      //
      // The File menu's wording, not one of its own: it opens the same
      // picker and does the same thing, and two spellings of one command
      // is two things for somebody to wonder about the difference between.
      Button(String(localized: "Restore from Backup…", bundle: bundle, locale: locale,
                    comment: "First-run screen: opens the file picker"), action: restore)
        .controlSize(.large)
      Spacer(minLength: Theme.Space.m)
      Button(action: later) {
        Text(verbatim: String(localized: "Maybe later", bundle: bundle, locale: locale,
                              comment: "First-run screen: closes it"))
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textFaint)
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: - Previews

// One width only: this screen is fixed at the design's 600pt and has no
// narrow case to get wrong. Both appearances, because it is almost all
// text on a plain ground, which is where a missing colour token shows.

#Preview("Welcome") {
  WelcomeView(add: {}, restore: {}, later: {})
}

#Preview("Welcome, dark") {
  WelcomeView(add: {}, restore: {}, later: {})
    .preferredColorScheme(.dark)
}
