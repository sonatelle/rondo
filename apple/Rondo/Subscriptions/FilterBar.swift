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
    }
    .padding(.horizontal, Theme.Space.section)
    .padding(.vertical, Theme.Space.m)
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
