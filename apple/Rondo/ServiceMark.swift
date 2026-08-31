import SwiftUI

/// The rounded block that stands in for a service, carrying its initials.
///
/// Letters rather than logos, permanently. Bundling each service's mark
/// would put other people's trademarks in an MIT repository, and the design
/// says the same: the letter block is the sanctioned answer, not a
/// placeholder waiting for artwork.
struct ServiceMark: View {
  let name: String
  var side: CGFloat = 28

  var body: some View {
    RoundedRectangle(cornerRadius: side * 0.29, style: .continuous)
      .fill(palette.background)
      .frame(width: side, height: side)
      .overlay {
        Text(ServiceMark.initials(of: name))
          .font(.system(size: side * 0.43, weight: .semibold))
          .foregroundStyle(palette.foreground)
          .minimumScaleFactor(0.7)
          .lineLimit(1)
      }
  }

  /// One of the design's four blocks, chosen from the name.
  ///
  /// A stable choice rather than a meaningful one: until categories reach
  /// the interface this only has the name to go on, and a block whose
  /// colour changed between launches would read as a different service.
  private var palette: (background: Color, foreground: Color) {
    switch abs(name.hashValue) % 4 {
    case 0: (.iconBlueBackground, .iconBlueForeground)
    case 1: (.iconNeutralBackground, .iconNeutralForeground)
    case 2: (.iconWarmBackground, .iconWarmForeground)
    default: (.iconGreenBackground, .iconGreenForeground)
    }
  }

  /// What to write in the block.
  ///
  /// One character, except where a name opens in camel case - "iCloud+"
  /// reads as "iC" and not as "I", which is what the design shows and what
  /// tells iCloud from iA Writer at a glance. Anything not written in an
  /// alphabet with letter case, Chinese among them, keeps its first
  /// character as it is.
  static func initials(of name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.first else {
      return ""
    }
    let rest = trimmed.dropFirst()
    if first.isLowercase, let second = rest.first, second.isUppercase {
      return String(first) + String(second)
    }
    return first.isCased ? String(first).uppercased() : String(first)
  }
}

private extension Character {
  /// Whether this character belongs to an alphabet that has cases at all.
  ///
  /// Uppercasing a Chinese character is a no-op, but asking the question
  /// keeps the intent legible: only a cased letter gets capitalised.
  var isCased: Bool {
    isLowercase || isUppercase
  }
}
