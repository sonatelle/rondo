import SwiftUI

/// What the list is narrowed to, beyond the page it is on.
///
/// Two pills, not the design's three. The third is a status - "active" -
/// and the sidebar already decides that: everywhere but the archive shows
/// what is still being paid for. Two controls over one thing is one too
/// many, and when they disagreed nobody could say which won. What is left
/// is what the sidebar cannot answer: which shop it was bought from, and
/// which currency it is charged in.
///
/// A pill is tinted while it is narrowing something, so a list that looks
/// short says why it is short.
struct FilterBar: View {
  @Binding var channel: ChannelFilter
  @Binding var currency: String?

  /// The choices worth offering, which is what the rows actually hold:
  /// a filter for a channel nothing was bought through would return an
  /// empty list and teach nobody anything.
  let channels: [ChannelFilter]
  let currencies: [String]

  /// What the rows on screen come to a month, per currency, worked out by
  /// the core over exactly the rows the filters left.
  let totals: [SpendingSummary]

  /// The same rows as one figure in the primary currency, when the rates
  /// reach far enough. Nothing here when they do not, and the per-currency
  /// list is shown instead.
  let converted: ConvertedSpending?

  var body: some View {
    HStack(spacing: Theme.Space.s) {
      FilterPill(
        title: channelTitle,
        isNarrowing: channel != .any,
        options: ([.any] + channels).map { option in
          FilterOption(title: title(of: option), isChosen: option == channel) {
            channel = option
          }
        }
      )
      FilterPill(
        title: currency ?? String(localized: "All currencies", bundle: Localization.bundle,
                                  locale: Localization.locale,
                                  comment: "The currency filter, while it narrows nothing"),
        isNarrowing: currency != nil,
        options: [
          FilterOption(
            title: String(localized: "All currencies", bundle: Localization.bundle,
                          locale: Localization.locale,
                          comment: "The currency filter, while it narrows nothing"),
            isChosen: currency == nil
          ) { currency = nil },
        ] + currencies.map { code in
          FilterOption(title: code, isChosen: currency == code) { currency = code }
        }
      )
      Spacer(minLength: Theme.Space.m)
      levelled
    }
    .padding(.horizontal, Theme.Space.section)
    .padding(.vertical, Theme.Space.m)
  }

  /// What the filtered rows come to a month, at the far end of the bar.
  ///
  /// Beside the filters rather than under the table, which is where the
  /// design puts it and which is also the only place it reads correctly:
  /// a total sitting next to the controls that narrowed the list is
  /// understood to be the total of what they left, and now it is.
  ///
  /// One figure where the rates allow it, and the per-currency list where
  /// they do not - never a converted total that quietly omits rows. When
  /// some currencies converted and others did not, the figure is shown with
  /// a marker saying so, because a total missing three subscriptions looks
  /// exactly like a smaller total.
  @ViewBuilder
  private var levelled: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    if let converted, converted.subscriptionCount > 0 {
      HStack(spacing: Theme.Space.xs) {
        Text(verbatim: String(localized: "Levelled monthly", bundle: bundle, locale: locale,
                              comment: "Label on the total beside the filters"))
          .foregroundStyle(Color.textMuted)
        Text(verbatim: Formatting.amount(converted.monthly, currency: converted.currency))
          .fontWeight(.semibold)
          .monospacedDigit()
          .foregroundStyle(Color.textPrimary)
          .lineLimit(1)
        if !converted.unconverted.isEmpty {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.danger)
            .help(omissionNote(converted))
        }
      }
      .font(Theme.Font.caption)
    } else if !totals.isEmpty {
      HStack(spacing: Theme.Space.xs) {
        Text(verbatim: String(localized: "Levelled monthly", bundle: bundle, locale: locale,
                              comment: "Label on the total beside the filters"))
          .foregroundStyle(Color.textMuted)
        ForEach(Array(totals.enumerated()), id: \.element.currency) { index, total in
          if index > 0 {
            Text(verbatim: "·")
              .foregroundStyle(Color.textFaint)
          }
          Text(verbatim: Formatting.amount(total.monthly, currency: total.currency))
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
        }
      }
      .font(Theme.Font.caption)
    }
  }

  /// Which currencies the figure beside it leaves out.
  private func omissionNote(_ converted: ConvertedSpending) -> String {
    let left = converted.unconverted.reduce(0) { $0 + Int($1.subscriptionCount) }
    let codes = converted.unconverted.map(\.currency).joined(separator: ", ")
    return String(localized: "\(left) not included: no rate for \(codes)",
                  bundle: Localization.bundle, locale: Localization.locale,
                  comment: "Under a total, naming the currencies it leaves out")
  }

  private var channelTitle: String {
    title(of: channel)
  }

  private func title(of filter: ChannelFilter) -> String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return switch filter {
    case .any:
      String(localized: "All channels", bundle: bundle, locale: locale,
             comment: "The channel filter, while it narrows nothing")
    case .unrecorded:
      String(localized: "Not recorded", bundle: bundle, locale: locale,
             comment: "No payment method was said")
    case let .bought(channel):
      channel.title
    }
  }
}

/// Which shop a subscription was bought from, as a filter.
///
/// Three cases rather than an optional channel, because "any" and "nobody
/// said" are different questions and an `Optional` has only one nil.
enum ChannelFilter: Hashable {
  case any
  case unrecorded
  case bought(Channel)

  /// Whether a subscription passes this filter.
  func matches(_ subscription: Subscription) -> Bool {
    switch self {
    case .any: true
    case .unrecorded: subscription.channel == nil
    case let .bought(channel): subscription.channel == channel
    }
  }
}

/// One choice inside a pill's popover.
struct FilterOption: Identifiable {
  let title: String
  let isChosen: Bool
  let choose: () -> Void

  var id: String {
    title
  }
}

/// A pill that opens its choices.
///
/// The same button-and-popover the form's pickers use rather than a `Menu`,
/// which macOS insists on drawing its own way: bare words with an indicator
/// on the leading edge, ignoring any background given to the label.
private struct FilterPill: View {
  let title: String
  let isNarrowing: Bool
  let options: [FilterOption]

  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      HStack(spacing: Theme.Space.xs) {
        Text(verbatim: title)
          .font(Theme.Font.caption)
          .fontWeight(isNarrowing ? .medium : .regular)
          .foregroundStyle(isNarrowing ? Color.white : Color.textPrimary)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: 9))
          .foregroundStyle(isNarrowing ? Color.white.opacity(0.8) : Color.textFaint)
      }
      .padding(.horizontal, 11)
      .frame(height: 26)
      .background(isNarrowing ? Color.brand : Color.hoverBackground, in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(options) { option in
          PickerRow(title: option.title, isChosen: option.isChosen) {
            option.choose()
            isPresented = false
          }
        }
      }
      .padding(Theme.Space.m)
      .frame(width: 200)
      .background(Color.surface)
      .multilineTextAlignment(.leading)
    }
  }
}
