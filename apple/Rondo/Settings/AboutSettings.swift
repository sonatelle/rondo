import SwiftUI

struct AboutSettings: View {
  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return Form {
      Section {
        identity
          .frame(maxWidth: .infinity)
          .padding(.vertical, Theme.Space.m)
      }

      Section(String(localized: "Links", bundle: bundle, locale: locale,
                     comment: "Settings section: where the project lives"))
      {
        AboutLink(
          String(localized: "Source", bundle: bundle, locale: locale,
                 comment: "Link to the repository"),
          systemImage: "curlybraces",
          tint: .navAll,
          to: "https://github.com/sonatelle/rondo"
        )
        AboutLink(
          String(localized: "Releases", bundle: bundle, locale: locale,
                 comment: "Link to the published versions"),
          systemImage: "shippingbox",
          tint: .navAnalytics,
          to: "https://github.com/sonatelle/rondo/releases"
        )
        AboutLink(
          String(localized: "Report an issue", bundle: bundle, locale: locale,
                 comment: "Link to the issue tracker"),
          systemImage: "ladybug",
          tint: .categoryCyan,
          to: "https://github.com/sonatelle/rondo/issues"
        )
      }

      Section {
        Text(verbatim: String(localized: "© 2026 Sonatelle · aliaxy · MIT License",
                              bundle: bundle, locale: locale,
                              comment: "Foot of the about tab"))
          .font(Theme.Font.caption)
          .foregroundStyle(Color.textFaint)
          .frame(maxWidth: .infinity)
      }
    }
    .formStyle(.grouped)
  }

  private var identity: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return VStack(spacing: Theme.Space.xs) {
      // The app's own icon, read from the bundle rather than drawn again,
      // so it cannot drift from what the Dock shows.
      if let icon = NSImage(named: "AppIcon") {
        Image(nsImage: icon)
          .resizable()
          .frame(width: 72, height: 72)
          .padding(.bottom, Theme.Space.xs)
      }
      Text(verbatim: "Rondo")
        .font(.system(size: 17, weight: .semibold))
      Text(Self.version)
        .font(Theme.Font.caption)
        .foregroundStyle(Color.textMuted)
        .monospacedDigit()
      // The core carries its own version and moves on its own schedule,
      // so the two differing is normal. What it catches is a bundle built
      // against a stale XCFramework: an app several releases along still
      // reporting the core it shipped with on day one.
      Text(verbatim: String(localized: "Core \(Self.coreVersion)", bundle: bundle, locale: locale,
                            comment: "The version the Rust core reports"))
        .font(Theme.Font.footnote)
        .foregroundStyle(Color.textFaint)
        .monospacedDigit()
      Text(verbatim: String(
        localized: "A theme that keeps returning — and so does every subscription.",
        bundle: bundle, locale: locale, comment: "What the name means"
      ))
      .font(Theme.Font.caption)
      .foregroundStyle(Color.textMuted)
      .multilineTextAlignment(.center)
      .padding(.top, Theme.Space.s)
      Text(verbatim: String(
        localized: "Everything stays in one file on this Mac. No cloud, no account, no network.",
        bundle: bundle, locale: locale, comment: "The promise about data, in the about tab"
      ))
      .font(Theme.Font.footnote)
      .foregroundStyle(Color.textFaint)
      .multilineTextAlignment(.center)
    }
  }

  /// Read from the bundle rather than written here, so it cannot disagree
  /// with what was actually built and released.
  ///
  /// The numbers come from the bundle; the word in front of them comes
  /// from the catalogue. Written as one Swift string, as this was, the
  /// word could only ever be "Version".
  private static var version: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "—"
    let build = info?["CFBundleVersion"] as? String ?? "—"
    return String(
      localized: "Version \(short) (\(build))",
      bundle: Localization.bundle,
      locale: Localization.locale
    )
  }

  /// What the linked Rust core reports about itself.
  private static var coreVersion: String {
    libraryVersion()
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
  /// Already through the catalogue, like every other word in the app: a
  /// key would be resolved against the system's language rather than the
  /// chosen one.
  let title: String
  let systemImage: String
  let tint: Color
  let destination: URL

  init(_ title: String, systemImage: String, tint: Color, to address: String) {
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
        Text(verbatim: title)
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
