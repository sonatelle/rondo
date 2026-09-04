import Foundation

/// Databases for Xcode previews, filled in memory.
///
/// Previews exist here for one reason: until now the only way to find out
/// whether a layout survived a narrow window was to build the app, run it,
/// and look - which in practice meant asking somebody else to look. A
/// preview pinned to a width answers that question without leaving the
/// editor, and a layout that breaks at 760 points is then a thing to see
/// rather than a thing to be told about.
///
/// Compiled into the app rather than kept behind `#if DEBUG`, because the
/// preview canvas builds the same target either way and the cost is one
/// small file. Nothing in the shipping interface calls it.
enum PreviewData {
  /// A database with a spread wide enough to show the layouts apart:
  /// three currencies so the stacked figures are three lines, a yearly
  /// plan so the levelled and charged cards disagree, one archived, and
  /// one whose first charge has not arrived.
  @MainActor
  static func populated() -> SubscriptionsModel {
    let model = empty()
    let today = Date()
    let calendar = Calendar.current

    func draft(
      _ name: String,
      _ amount: String,
      _ currency: String,
      inDays: Int,
      unit: CycleUnit = .month,
      template: String? = nil
    ) -> NewSubscription {
      let date = calendar.date(byAdding: .day, value: inDays, to: today) ?? today
      return NewSubscription(
        name: name,
        amount: amount,
        currency: currency,
        cycleCount: 1,
        cycleUnit: unit,
        firstBillingDate: Formatting.civilDate(from: date),
        notes: nil,
        templateId: template,
        categoryId: model.categories.first { $0.iconKey == "ai" }?.id,
        reminderLeadDays: nil
      )
    }

    // Started a year ago, so it has a history to have cost something.
    _ = model.add(draft("Netflix", "15.90", "USD", inDays: -365, template: "netflix"))
    _ = model.add(draft("网易云音乐", "88.00", "CNY", inDays: -300, unit: .year))
    _ = model.add(draft("ChatGPT", "499.99", "TRY", inDays: 2))
    _ = model.add(draft("Grok", "700", "INR", inDays: 14))
    _ = model.add(draft("Figma", "12.00", "USD", inDays: 6))
    return model
  }

  /// A database with nothing in it, for the empty states.
  @MainActor
  static func empty() -> SubscriptionsModel {
    // A preview that cannot open a database has nothing to show and no way
    // to say so, so failing loudly here is better than a blank canvas.
    let rondo = try! Rondo.openInMemory()
    return SubscriptionsModel(rondo: rondo)
  }
}
