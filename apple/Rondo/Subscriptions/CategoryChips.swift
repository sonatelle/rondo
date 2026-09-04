import SwiftUI

/// The categories, as a row of capsules with one of them chosen.
///
/// Chips rather than a menu because there are eight of them and they fit:
/// a menu would hide which one is chosen behind a click, and filing
/// something is the sort of decision people change their mind about twice
/// before saving.
///
/// Choosing the chosen one again clears it. That is the only way to say
/// "actually, none of these" without a chip of its own, and it matches
/// what a set of capsules leads people to try.
struct CategoryChips: View {
  let categories: [Category]
  @Binding var selection: Uuid?

  var body: some View {
    // Wrapping, because eight categories in two languages do not fit on
    // one line at every window width, and a row that clips is a row that
    // hides a choice.
    FlowLayout(spacing: Theme.Space.s) {
      ForEach(categories, id: \.id) { category in
        FormChip(
          title: Categories.name(category.name, iconKey: category.iconKey),
          symbol: Categories.symbol(for: category.iconKey),
          tint: Categories.tint(for: category.colorKey),
          isSelected: selection == category.id
        ) {
          selection = selection == category.id ? nil : category.id
        }
      }
    }
  }
}

/// Lays out its children in rows, wrapping when one runs out of width.
///
/// SwiftUI has no flow layout of its own, and an `HStack` in a form row
/// either clips or forces the sheet wider. This is the smallest thing that
/// does the job: measure each child, start a new line when the next one
/// would not fit.
struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    let rows = arrange(subviews: subviews, in: width)
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
    let widest = rows.map(\.width).max() ?? 0
    return CGSize(width: min(width, widest), height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache _: inout ()
  ) {
    let rows = arrange(subviews: subviews, in: proposal.width ?? bounds.width)
    var y = bounds.minY
    for row in rows {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(
          at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
          proposal: ProposedViewSize(size)
        )
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  /// One line's worth of children, and how tall it is.
  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(subviews: Subviews, in width: CGFloat) -> [Row] {
    var rows: [Row] = []
    var current = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let next = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      if next > width, !current.indices.isEmpty {
        rows.append(current)
        current = Row()
      }
      current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      current.height = max(current.height, size.height)
      current.indices.append(index)
    }
    if !current.indices.isEmpty {
      rows.append(current)
    }
    return rows
  }
}
