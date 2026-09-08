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
  @AppStorage(Preference.autoUpdateRates) private var autoUpdateRates = true
  @AppStorage(Preference.lockHistoricalRates) private var lockHistoricalRates = true

  /// The currency whose rates are being looked at, if any.
  @State private var inspecting: String?

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale

    return Form {
      Section {
        // The form's picker rather than a `Picker`, because it searches:
        // this is a list of roughly a hundred and fifty codes, and a menu
        // that long is only usable by somebody who already knows where
        // their currency sits in it. Written once in round 7 and reused
        // here rather than built again.
        LabeledContent {
          HStack(spacing: Theme.Space.s) {
            CurrencyPicker(currency: chosenCurrency)
            if !primaryCurrency.isEmpty {
              Button {
                primaryCurrency = ""
              } label: {
                Text(verbatim: String(localized: "Follow the system", bundle: bundle,
                                      locale: locale,
                                      comment: "Take this setting from the Mac's own"))
              }
              .buttonStyle(.link)
              .font(.caption)
            }
          }
        } label: {
          Text(verbatim: String(localized: "Primary currency", bundle: bundle, locale: locale,
                                comment: "Setting: the currency every total is shown in"))
        }
        Text(verbatim: String(
          localized: "Every total is converted into this currency. Amounts are still recorded in the currency they are billed in.",
          bundle: bundle, locale: locale, comment: "Under the primary currency setting"
        ))
        .font(.caption)
        .foregroundStyle(.secondary)

        Toggle(String(localized: "Update rates automatically", bundle: bundle, locale: locale,
                      comment: "Setting: fetch new exchange rates without being asked"),
               isOn: $autoUpdateRates)
        Text(verbatim: String(localized: "Once a day, when there is a connection.",
                              bundle: bundle, locale: locale,
                              comment: "Under the automatic rate update setting"))
          .font(.caption)
          .foregroundStyle(.secondary)

        Toggle(String(localized: "Price past charges at the rate of their day",
                      bundle: bundle, locale: locale,
                      comment: "Setting: whether history is converted at the rates of the time"),
               isOn: $lockHistoricalRates)
        Text(verbatim: lockedExplanation)
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
            // Not disabled while fetching. `refreshRates` already refuses
            // to start a second one, and a control that disables itself
            // mid-press is a control that sometimes does not respond -
            // pressing it with a trackpad tap, which is a much shorter
            // press than a click, was landing on nothing.
            if model.isRefreshingRates {
              ProgressView().controlSize(.small)
            }
          }

          if let failure = model.rateFailure {
            Text(verbatim: failure)
              .font(.caption)
              .foregroundStyle(Color.danger)
          } else if let note = model.rateNote {
            Text(verbatim: note)
              .font(.caption)
              .foregroundStyle(.secondary)
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
              CurrencyRateRow(
                model: model,
                currency: code,
                // Handed in rather than read from the defaults inside the
                // row. A row that reads a global is a row SwiftUI has no
                // reason to redraw when the global changes: after
                // switching from dollars to yuan, every rate already on
                // screen went on saying "USD" while the one row that
                // happened to be new said "CNY".
                primary: chosenCurrency.wrappedValue,
                inspecting: $inspecting
              )
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
    // Changing which currency totals are in changes every figure in the
    // app, and needs a rate for the new one that may never have been
    // fetched. Neither happened on its own: the window kept the old
    // numbers until it was made to redraw, and Update found nothing to do
    // because another currency already had today's rate.
    .onChange(of: primaryCurrency) { _, _ in
      guard let model else { return }
      model.reload()
      Task { await model.refreshRates() }
    }
  }

  /// The primary currency as a picker sees it.
  ///
  /// The stored value is empty while it follows the system, which a picker
  /// would show as a blank chip. This resolves it for display and writes
  /// the choice straight through, so picking the system's own currency
  /// explicitly is a real choice rather than a no-op.
  private var chosenCurrency: Binding<String> {
    Binding(
      get: { primaryCurrency.isEmpty ? Currencies.preferred : primaryCurrency },
      set: { primaryCurrency = $0 }
    )
  }

  /// What turning the history switch off actually does.
  ///
  /// Written as a consequence rather than as a description. "Off, history
  /// uses today's rate" is true and tells nobody anything; what somebody
  /// needs to know before flipping it is that a figure they have been
  /// reading as settled will start moving.
  private var lockedExplanation: String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return lockHistoricalRates
      ? String(localized: "What you have already been charged does not change when rates do.",
               bundle: bundle, locale: locale,
               comment: "Under the historical rate setting, while it is on")
      : String(localized: "Everything is priced at today's rate, so past totals move as rates do.",
               bundle: bundle, locale: locale,
               comment: "Under the historical rate setting, while it is off")
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

/// One currency, its rate against the primary one, and a way to overrule it.
///
/// Read as the pair a person compares against their bank - "1 USD = 7.1240
/// CNY" - rather than in the form it is stored in, which is against a fixed
/// base neither of them may be. The core turns one into the other; nothing
/// here divides.
///
/// Everything it draws comes from the model, which is observed. A row that
/// asked the database for its own rate looked right until a fetch landed
/// after it had drawn: the call was not observable state, so the row never
/// heard about the answer and sat blank under a note saying rates had been
/// updated.
private struct CurrencyRateRow: View {
  let model: SubscriptionsModel
  let currency: String
  /// The currency this rate is quoted against.
  let primary: String
  @Binding var inspecting: String?

  /// What is in the field. Seeded from the reading and re-seeded whenever
  /// it changes, so a fetch that lands while this is on screen is picked
  /// up - but held separately so typing is not overwritten mid-keystroke.
  @State private var typed = ""
  @State private var refusal: String?

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    let today = model.referenceDay
    let reading = model.rateReadings[currency]
    let isManual = reading?.isManual == true

    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: Theme.Space.s) {
        Text(verbatim: "1 \(currency)")
          .frame(width: 96, alignment: .leading)
        Text(verbatim: "=")
          .foregroundStyle(.secondary)
        TextField(
          String(localized: "Rate", bundle: bundle, locale: locale,
                 comment: "Field for typing an exchange rate by hand"),
          text: $typed
        )
        .labelsHidden()
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 88)
        // Blue, not red. The design is explicit that warm red is kept for
        // a charge three days out or nearer; typing a rate is a decision,
        // not an alarm.
        .overlay(
          RoundedRectangle(cornerRadius: 5)
            .strokeBorder(isManual ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .onSubmit { store(on: today) }
        Text(verbatim: primary)
          .frame(width: 38, alignment: .leading)
          .foregroundStyle(.secondary)

        Spacer(minLength: Theme.Space.s)
        Text(verbatim: status(isManual: isManual, hasRate: reading?.pair != nil))
          .font(.caption)
          .foregroundStyle(isManual ? Color.accentColor : .secondary)
        if isManual {
          Button {
            model.deleteRate(currency: currency, on: today)
          } label: {
            Text(verbatim: String(localized: "Use the fetched rate", bundle: bundle,
                                  locale: locale,
                                  comment: "Button: drop a hand-entered rate so a fetch can fill it in again"))
          }
          .buttonStyle(.link)
          .font(.caption)
        }
      }
      if let refusal {
        Text(verbatim: refusal)
          .font(.caption)
          .foregroundStyle(Color.danger)
      }
    }
    .onAppear { typed = shown(reading) }
    // The reading is observable state, so this fires when a fetch lands,
    // when a rate is typed, and when the primary currency changes - the
    // three ways the number in the field can stop being true.
    .onChange(of: reading) { _, now in
      typed = shown(now)
      refusal = nil
    }
  }

  /// The reading as the field shows it: shortened, or empty when there is
  /// no rate rather than a zero that would read as one.
  private func shown(_ reading: SubscriptionsModel.RateReading?) -> String {
    reading?.pair.map(Formatting.rate) ?? ""
  }

  /// Stores what was typed, or says why it could not be.
  private func store(on day: CivilDate) {
    guard !typed.isEmpty else { return }
    if let failure = model.setManualPairRate(
      of: currency, against: primary, on: day, rate: typed
    ) {
      refusal = failure
    } else {
      refusal = nil
      inspecting = nil
    }
  }

  /// Whether this rate was fetched or typed, in a word.
  private func status(isManual: Bool, hasRate: Bool) -> String {
    let bundle = Localization.bundle
    let locale = Localization.locale
    if !hasRate {
      return String(localized: "No rate", bundle: bundle, locale: locale,
                    comment: "Shown for a currency nothing can be converted from yet")
    }
    return isManual
      ? String(localized: "Yours", bundle: bundle, locale: locale,
               comment: "Beside a rate the person typed themselves")
      : String(localized: "Fetched", bundle: bundle, locale: locale,
               comment: "Beside a rate that came from the source")
  }
}
