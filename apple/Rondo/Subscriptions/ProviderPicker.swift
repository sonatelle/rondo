import SwiftUI

/// Picks a bundled service, or says this is one the list does not carry.
///
/// A searchable panel rather than a menu, because the catalogue is long
/// enough that scanning it is slower than typing three letters, and because
/// searching is where the core's alias matching earns its keep: "B站" finds
/// Bilibili, and no menu could have offered that.
///
/// Picking a service only **prefills**. The name, the category and
/// everything else stay editable afterwards, and choosing "Custom" clears
/// the name for somebody to write their own.
struct ProviderPicker: View {
  /// The categories a template's own key is matched against, so picking a
  /// service can file it.
  let categories: [Category]

  /// Which templates this database has already used, most recent first.
  /// Offered above the rest, and absent when there are none.
  let recents: [ServiceTemplate]

  @Binding var selection: String?
  @Binding var name: String
  @Binding var categoryID: Uuid?

  @State private var isPresented = false
  @State private var query = ""

  /// How many recents are worth offering before the list is just the
  /// catalogue in a different order.
  private static let recentsShown = 4

  var body: some View {
    Button {
      isPresented = true
    } label: {
      HStack(spacing: Theme.Space.m) {
        ServiceMark(name: chosen?.name ?? "", side: 20)
        Text(chosenLabel)
          .font(Theme.Font.body)
          .foregroundStyle(Color.textPrimary)
          .lineLimit(1)
        Spacer(minLength: Theme.Space.xs)
        Image(systemName: "chevron.down")
          .font(.system(size: 10))
          .foregroundStyle(Color.textFaint)
      }
      .padding(.horizontal, Theme.Space.m)
      .frame(height: 29)
      .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      panel
    }
  }

  /// The service currently chosen, or nothing when this is a custom entry.
  private var chosen: ServiceTemplate? {
    guard let selection else { return nil }
    return searchServiceTemplates(query: "").first { $0.id == selection }
  }

  /// Verbatim for a service's own name, which is data; through the
  /// catalogue for the word that stands in when there is none.
  private var chosenLabel: String {
    chosen?.name
      ?? String(
        localized: "Custom",
        bundle: Localization.bundle,
        locale: Localization.locale,
        comment: "Provider picker: a service the bundled list does not carry"
      )
  }

  private var panel: some View {
    VStack(spacing: 0) {
      TextField(
        String(
          localized: "Search services",
          bundle: Localization.bundle,
          locale: Localization.locale,
          comment: "Provider picker's search field"
        ),
        text: $query
      )
      .textFieldStyle(.plain)
      .font(Theme.Font.body)
      .padding(.horizontal, Theme.Space.l)
      .frame(height: 29)
      .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
      .padding(Theme.Space.l)

      Divider().foregroundStyle(Color.separatorLine)

      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          // Recents are worth offering only when nothing has been typed:
          // once there is a query, what matches it is the whole answer.
          if query.isEmpty, !recents.isEmpty {
            GroupTitle(text: String(localized: "Recently used", bundle: Localization.bundle,
                                    locale: Localization.locale,
                                    comment: "Provider picker: the services already in use"))
            ForEach(recents.prefix(Self.recentsShown), id: \.id) { row($0) }
            GroupTitle(text: String(localized: "All services", bundle: Localization.bundle,
                                    locale: Localization.locale,
                                    comment: "Provider picker: the whole bundled catalogue"))
          }
          ForEach(matches, id: \.id) { row($0) }
          if matches.isEmpty {
            Text(verbatim: String(localized: "No service by that name",
                                  bundle: Localization.bundle, locale: Localization.locale,
                                  comment: "The search matched nothing"))
              .font(Theme.Font.caption)
              .foregroundStyle(Color.textMuted)
              .padding(.horizontal, Theme.Space.m)
              .padding(.vertical, Theme.Space.l)
          }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.m)
      }
      // A fixed height rather than a maximum: a popover measures itself
      // when it opens and keeps that size, so a list that grew back after
      // a search was cleared stayed clipped to the shorter one's height.
      .frame(height: 280)

      Divider().foregroundStyle(Color.separatorLine)
      customRow
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.m)
    }
    .frame(width: 340)
    .background(Color.surface)
    .multilineTextAlignment(.leading)
  }

  /// What the query matches, ranked by the core so every frontend finds the
  /// same things in the same order.
  private var matches: [ServiceTemplate] {
    searchServiceTemplates(query: query)
  }

  private func row(_ template: ServiceTemplate) -> some View {
    let isChosen = selection == template.id
    return Button {
      choose(template)
    } label: {
      HStack(spacing: Theme.Space.l) {
        ServiceMark(name: template.name, side: 22)
        Text(verbatim: template.name)
          .font(Theme.Font.body)
          .foregroundStyle(Color.textPrimary)
          .lineLimit(1)
        Spacer(minLength: Theme.Space.xs)
        if isChosen {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.brand)
        }
      }
      .padding(.horizontal, Theme.Space.m)
      .padding(.vertical, Theme.Space.s)
      .background(
        isChosen ? Color.surfaceRaised : .clear,
        in: RoundedRectangle(cornerRadius: Theme.Radius.sidebarItem)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var customRow: some View {
    Button {
      chooseCustom()
    } label: {
      HStack(spacing: Theme.Space.l) {
        Image(systemName: "plus")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.textSecondary)
          .frame(width: 22, height: 22)
          .background(Color.hoverBackground, in: RoundedRectangle(cornerRadius: 6))
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: String(localized: "Custom…", bundle: Localization.bundle,
                                locale: Localization.locale,
                                comment: "The row for a service the list does not carry"))
            .font(Theme.Font.body)
            .fontWeight(.medium)
            .foregroundStyle(Color.textPrimary)
          Text(verbatim: String(
            localized: "A service the list does not carry; write the name yourself",
            bundle: Localization.bundle, locale: Localization.locale,
            comment: "Under the custom row, in the provider picker"
          ))
          .font(Theme.Font.footnote)
          .foregroundStyle(Color.textMuted)
          .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Theme.Space.m)
      .padding(.vertical, Theme.Space.s)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// Fills in what a chosen service knows.
  ///
  /// The name is always overwritten. Picking a service from this list is
  /// somebody saying which service this is, and the name is the first
  /// thing they said it was; leaving a previous pick's name behind because
  /// it might have been typed by hand guesses wrong more often than it
  /// guesses right. Somebody who wants their own wording writes it after,
  /// or picks Custom, which is the one choice that leaves the name alone.
  private func choose(_ template: ServiceTemplate) {
    selection = template.id
    name = template.name
    // The template names its category by the same key a category's icon
    // carries, which is how picking Netflix files it under Video. It moves
    // with the name for the same reason: a service the person just changed
    // their mind about should not leave the last one's category behind.
    //
    // A key no category matches - one since deleted, or renamed - leaves
    // the field as it was rather than emptying it, since "I could not work
    // this out" is not the same answer as "none of these".
    if let matched = categories.first(where: { $0.iconKey == template.defaultCategory }) {
      categoryID = matched.id
    }
    isPresented = false
  }

  /// Custom is a choice, not the absence of one, so it clears the name it
  /// prefilled rather than leaving another service's behind.
  private func chooseCustom() {
    if let chosen, name == chosen.name {
      name = ""
    }
    selection = nil
    isPresented = false
  }
}

/// A group heading inside the panel.
private struct GroupTitle: View {
  /// Already through the catalogue; see `FormRow.label`.
  let text: String

  var body: some View {
    Text(verbatim: text)
      .font(Theme.Font.groupTitle)
      .foregroundStyle(Color.textMuted)
      .padding(.horizontal, Theme.Space.m)
      .padding(.top, Theme.Space.m)
      .padding(.bottom, Theme.Space.xs)
  }
}
