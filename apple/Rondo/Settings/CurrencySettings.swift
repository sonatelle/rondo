import SwiftUI

/// Which currency totals are shown in, and where the rates come from.
///
/// A tab of its own rather than three more rows under General, because
/// this is the one setting that reaches the network and the person is
/// owed a plain view of what that means: what was fetched, when, and a way
/// to overrule it.
struct CurrencySettings: View {
  /// The open database, or nothing when it could not be opened.
  ///
  /// Handed over rather than reached for through the environment. Asking
  /// the environment for it crashed the moment this tab was clicked: the
  /// settings scene is separate from the window scene and was never given
  /// one, and `@Environment(SubscriptionsModel.self)` traps rather than
  /// returning nil when nothing supplies it.
  let model: SubscriptionsModel?

  @AppStorage(Preference.primaryCurrency) private var primaryCurrency = ""

  /// The currency whose rates are being looked at, if any.
  @State private var inspecting: String?

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale

    return Form {
      Section {
        Picker(String(localized: "Primary currency", bundle: bundle, locale: locale,
                      comment: "Setting: the currency every total is shown in"),
               selection: $primaryCurrency)
        {
          Text(verbatim: String(localized: "Follow the system", bundle: bundle, locale: locale,
                                comment: "Take this setting from the Mac's own")).tag("")
          Divider()
          ForEach(Currencies.all, id: \.self) { code in
            Text(verbatim: code).tag(code)
          }
        }
        Text(verbatim: String(
          localized: "Every total is converted into this currency, at the rate of the day each charge fell on. Amounts are still recorded in the currency they are billed in.",
          bundle: bundle, locale: locale, comment: "Under the primary currency setting"
        ))
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if let model {
        Section {
          LabeledContent {
            Text(verbatim: lastUpdated(of: model))
              .foregroundStyle(model.newestRateDay == nil ? Color.danger : .secondary)
          } label: {
            Text(verbatim: String(localized: "Rates", bundle: bundle, locale: locale,
                                  comment: "Label for when exchange rates were last brought up to date"))
          }

          HStack {
            Button {
              Task { await model.refreshRates() }
            } label: {
              Text(verbatim: String(localized: "Update now", bundle: bundle, locale: locale,
                                    comment: "Button: fetch the latest exchange rates"))
            }
            .disabled(model.isRefreshingRates)

            if model.isRefreshingRates {
              ProgressView().controlSize(.small)
            }
          }

          if let failure = model.rateFailure {
            Text(verbatim: failure)
              .font(.caption)
              .foregroundStyle(Color.danger)
          }

          Text(verbatim: String(
            localized: "Rondo asks frankfurter.dev for rates against \(baseCurrency()) and nothing else. It sends nothing about you, and works offline on what it has already stored.",
            bundle: bundle, locale: locale,
            comment: "Under the rates section: what the one network request is"
          ))
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section {
          if model.currenciesInUse.isEmpty {
            Text(verbatim: String(
              localized: "Everything is already in \(baseCurrency()), so no rates are needed.",
              bundle: bundle, locale: locale,
              comment: "Shown when no subscription is in a currency needing conversion"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
          } else {
            ForEach(model.currenciesInUse, id: \.self) { code in
              CurrencyRateRow(model: model, currency: code, inspecting: $inspecting)
            }
          }
        } header: {
          Text(verbatim: String(localized: "Currencies in use", bundle: bundle, locale: locale,
                                comment: "Section listing the currencies subscriptions are billed in"))
        }
      } else {
        Section {
          Text(verbatim: String(
            localized: "Rates are unavailable because the database could not be opened.",
            bundle: bundle, locale: locale,
            comment: "Shown in the currency tab when the database failed to open"
          ))
          .font(.caption)
          .foregroundStyle(Color.danger)
        }
      }
    }
    .formStyle(.grouped)
  }

  /// When rates were last brought up to date, in words.
  private func lastUpdated(of model: SubscriptionsModel) -> String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    guard let day = model.newestRateDay else {
      return String(localized: "Never fetched", bundle: bundle, locale: locale,
                    comment: "No exchange rate has ever been stored")
    }
    return Formatting.date(day)
  }
}

/// One currency, the rate in force for it, and a way to overrule that.
///
/// The rate shown is the one in force *today*, which is the one a total on
/// screen right now was built from. Older days are still stored and still
/// used for older charges; this row is not the whole history and does not
/// pretend to be.
private struct CurrencyRateRow: View {
  let model: SubscriptionsModel
  let currency: String
  @Binding var inspecting: String?

  @State private var typed = ""

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    let today = model.referenceDay
    let stored = model.rates(for: currency).last { $0.effectiveOn <= today }

    return DisclosureGroup(isExpanded: expansion) {
      HStack {
        TextField(
          String(localized: "Rate", bundle: bundle, locale: locale,
                 comment: "Field for typing an exchange rate by hand"),
          text: $typed
        )
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 160)

        Button {
          if model.setManualRate(currency: currency, on: today, rate: typed) {
            inspecting = nil
          }
        } label: {
          Text(verbatim: String(localized: "Set", bundle: bundle, locale: locale,
                                comment: "Button: store the rate just typed"))
        }
        .disabled(typed.isEmpty)

        if stored?.isManual == true {
          Button {
            model.deleteRate(currency: currency, on: today)
            inspecting = nil
          } label: {
            Text(verbatim: String(localized: "Use the fetched rate", bundle: bundle, locale: locale,
                                  comment: "Button: drop a hand-entered rate so a fetch can fill it in again"))
          }
        }
      }
      Text(verbatim: String(
        localized: "One \(baseCurrency()) buys this many \(currency). A rate you set here is never overwritten by an update.",
        bundle: bundle, locale: locale, comment: "Explaining what a hand-entered rate means"
      ))
      .font(.caption)
      .foregroundStyle(.secondary)
    } label: {
      LabeledContent {
        HStack(spacing: 6) {
          if stored?.isManual == true {
            Image(systemName: "hand.raised.fill")
              .foregroundStyle(.secondary)
              .help(String(localized: "You set this rate yourself", bundle: bundle, locale: locale,
                           comment: "Tooltip on the marker beside a hand-entered rate"))
          }
          Text(verbatim: stored.map(\.rate) ?? String(
            localized: "No rate", bundle: bundle, locale: locale,
            comment: "Shown for a currency nothing can be converted from yet"
          ))
          .foregroundStyle(stored == nil ? Color.danger : .primary)
          .lineLimit(1)
        }
      } label: {
        Text(verbatim: currency)
      }
    }
  }

  /// Only one row is open at a time, so the list does not become a wall of
  /// fields; opening one loads its current rate into the box.
  private var expansion: Binding<Bool> {
    Binding(
      get: { inspecting == currency },
      set: { opened in
        if opened {
          typed = model.rates(for: currency).last { $0.effectiveOn <= model.referenceDay }?.rate ?? ""
          inspecting = currency
        } else if inspecting == currency {
          inspecting = nil
        }
      }
    )
  }
}
