import SwiftUI

/// Which page the window is showing, and what it is narrowed to.
///
/// This replaces the sidebar's old job of picking a status filter. The
/// design's sidebar is navigation - a page to be on - and the status is a
/// consequence of it: everywhere but the archive shows what is still being
/// paid for, because a list of what you subscribe to is not a place to be
/// reminded of what you cancelled.
///
/// Calendar and analytics are deliberately absent until the rounds that
/// build them. An entry that does nothing when clicked is worse than one
/// that has not arrived.
enum Navigation: Hashable, Identifiable {
  /// The three cards and what is charged next.
  case overview
  /// Everything still being paid for.
  case subscriptions
  /// Only what is filed under one category.
  case category(Uuid)
  /// What has been stopped, kept out of every total.
  case archived

  var id: Self {
    self
  }

  /// The title for a page that names itself, already in the reader's
  /// language. A category's title is its own name and comes from the
  /// category, so it is absent here.
  ///
  /// Resolved to a `String` rather than left as a key because the window
  /// title needs one, and keeping a second key-shaped copy for the sidebar
  /// would be the same words written twice, free to drift apart. The
  /// sidebar shows this verbatim, which is right: it has been through the
  /// catalogue already.
  var title: String? {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch self {
    case .overview:
      String(localized: "Overview", bundle: bundle, locale: locale,
             comment: "Sidebar page showing the cards and what is charged next")
    case .subscriptions:
      String(localized: "All Subscriptions", bundle: bundle, locale: locale,
             comment: "Sidebar page listing everything still being paid for")
    case .category: nil
    case .archived:
      String(localized: "Archived", bundle: bundle, locale: locale,
             comment: "Sidebar page for subscriptions that have been stopped")
    }
  }

  var symbol: String {
    switch self {
    case .overview: "square.grid.2x2.fill"
    case .subscriptions: "list.bullet"
    case .category: "tag.fill"
    case .archived: "archivebox.fill"
    }
  }

  /// The colour the sidebar tints this entry.
  ///
  /// Colour here marks what a page is, never how urgent something is: red
  /// and amber mean "charged soon" everywhere else in Rondo, and spending
  /// them on navigation would make that quieter.
  var tint: Color {
    switch self {
    case .overview: .navOverview
    case .subscriptions: .navAll
    case .category: .brand
    case .archived: .navArchived
    }
  }

  /// Which subscriptions this page is about, once the core has answered.
  func matches(_ renewal: Renewal) -> Bool {
    switch self {
    case .overview, .subscriptions:
      renewal.subscription.status == .active
    case let .category(id):
      renewal.subscription.status == .active && renewal.subscription.categoryId == id
    case .archived:
      renewal.subscription.status == .archived
    }
  }
}
