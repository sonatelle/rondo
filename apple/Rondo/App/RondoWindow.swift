import SwiftUI

/// How small the main window is allowed to get.
///
/// A window with no floor is a window whose layout has to work at every
/// width there is, which is not a thing anybody can check. Naming the
/// narrowest supported size turns that into one case to design for and one
/// preview to look at - and it is what every Mac app does: drag Finder or
/// Mail narrower and they stop.
///
/// The numbers are not a guess. The overview puts three cards in a row, and
/// a card has to stay wide enough for a currency amount on one line -
/// "US$1,499.99" at the figure size is about 130 points, and the padding
/// either side takes it to roughly 180. Three of those, the gaps between
/// them, the page margins and the sidebar are what the width below adds up
/// to. Below it the row would need to become something else, and a page
/// that rearranges itself twice is harder to hold in mind than one that
/// refuses to shrink.
enum RondoWindow {
  /// The narrowest the sidebar may be, matching what the split view asks
  /// for.
  static let minimumSidebarWidth: CGFloat = 180

  /// The narrowest the whole window may be.
  static let minimumWidth: CGFloat = minimumSidebarWidth + 600

  /// The shortest the window may be: enough for the three cards, the first
  /// row or two of what is coming, and the toolbar above them.
  static let minimumHeight: CGFloat = 460
}
