//! The object a frontend holds and calls into.

use std::path::PathBuf;
use std::sync::{Arc, Mutex, MutexGuard};

use jiff::civil::Date;
use rondo_core::Store;
use rondo_core::model::{
    BillingCycle, Category as CoreCategory, Money, Subscription as CoreSubscription,
    SubscriptionStatus,
};
use rust_decimal::Decimal;
use uuid::Uuid;

use crate::error::{Result, RondoError};
use crate::records::{
    Category, CategoryShare, MonthlySpending, PaymentMethod, Price, SpendingSummary, Subscription,
    SubscriptionTotal, WindowTotal,
};

/// An open Rondo database.
///
/// UniFFI shares an object as `Arc<Self>` and a frontend may call it from
/// whichever thread it likes, so the store sits behind a mutex. That also
/// matches SQLite: one connection, one operation at a time.
#[derive(uniffi::Object)]
pub struct Rondo {
    store: Mutex<Store>,
}

/// The fields a person fills in to create a subscription.
///
/// Identity and timestamps are deliberately absent: the core assigns them,
/// so a frontend cannot invent an id or backdate a record.
#[derive(Debug, Clone, uniffi::Record)]
pub struct NewSubscription {
    pub name: String,
    pub amount: Decimal,
    pub currency: String,
    pub cycle_count: u32,
    pub cycle_unit: rondo_core::model::CycleUnit,
    pub first_billing_date: Date,
    pub notes: Option<String>,
    pub template_id: Option<String>,
    pub category_id: Option<Uuid>,
    /// Days of warning before a renewal; the core's default when absent.
    pub reminder_lead_days: Option<u16>,
}

/// A subscription paired with the next date it will be charged.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Renewal {
    pub subscription: Subscription,
    /// The first charge falling on or after the day that was asked about.
    pub date: Date,
}

/// What restoring a backup changed.
///
/// The counts are `u32` because UniFFI has no `usize`; nobody is going to
/// keep four billion subscriptions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct ImportSummary {
    pub categories_added: u32,
    pub categories_updated: u32,
    pub subscriptions_added: u32,
    pub subscriptions_updated: u32,
}

impl From<rondo_core::backup::ImportReport> for ImportSummary {
    fn from(report: rondo_core::backup::ImportReport) -> Self {
        Self {
            categories_added: report.categories_added as u32,
            categories_updated: report.categories_updated as u32,
            subscriptions_added: report.subscriptions_added as u32,
            subscriptions_updated: report.subscriptions_updated as u32,
        }
    }
}

#[uniffi::export]
impl Rondo {
    /// Opens the database at `path`, creating and migrating it if needed.
    #[uniffi::constructor]
    pub fn open(path: String) -> Result<Arc<Self>> {
        let store = Store::open(&PathBuf::from(path))?;
        Ok(Arc::new(Self {
            store: Mutex::new(store),
        }))
    }

    /// Opens a database that lives only as long as this object.
    ///
    /// Frontends use this for previews and tests, where writing to the
    /// person's real file would be wrong.
    #[uniffi::constructor]
    pub fn open_in_memory() -> Result<Arc<Self>> {
        let store = Store::open_in_memory()?;
        Ok(Arc::new(Self {
            store: Mutex::new(store),
        }))
    }

    /// Lists subscriptions, archived ones included only when asked, each
    /// priced as of `on`.
    ///
    /// `on` is the frontend's own calendar day, for the same reason
    /// [`Self::renewals`] takes one: a subscription whose price rose in
    /// March costs one thing in February and another in April, and only the
    /// frontend knows which day the person is looking at.
    pub fn subscriptions(&self, on: Date, include_archived: bool) -> Result<Vec<Subscription>> {
        let filter = (!include_archived).then_some(SubscriptionStatus::Active);
        Ok(self
            .store()?
            .subscriptions(filter, on)?
            .into_iter()
            .map(Subscription::from)
            .collect())
    }

    /// Loads one subscription priced as of `on`, or nothing if that id is
    /// unknown.
    pub fn subscription(&self, id: Uuid, on: Date) -> Result<Option<Subscription>> {
        Ok(self.store()?.subscription(id, on)?.map(Subscription::from))
    }

    /// Records a new subscription and returns it as stored.
    pub fn add_subscription(&self, draft: NewSubscription) -> Result<Subscription> {
        let mut sub = CoreSubscription::new(
            &draft.name,
            Money::new(draft.amount, &draft.currency)?,
            BillingCycle::new(draft.cycle_count, draft.cycle_unit)?,
            draft.first_billing_date,
        )?;
        sub.notes = draft.notes;
        sub.template_id = draft.template_id;
        sub.category_id = draft.category_id;
        if let Some(days) = draft.reminder_lead_days {
            sub.reminder_lead_days = days;
        }
        self.store()?.insert_subscription(&sub)?;
        Ok(sub.into())
    }

    /// Saves an edited subscription and returns it with a fresh
    /// `updated_at`, which is the value the frontend should keep.
    ///
    /// A changed price **corrects** the entry in force on `on`; it does not
    /// record a rise. Mistyping a price is common and a rise is rare, and
    /// only the person knows which just happened, so recording a real
    /// change is a separate call: [`Self::add_price_change`].
    pub fn update_subscription(
        &self,
        subscription: Subscription,
        on: Date,
    ) -> Result<Subscription> {
        let sub = CoreSubscription::try_from(subscription)?;
        Ok(self.store()?.update_subscription(&sub, on)?.into())
    }

    /// Deletes a subscription; reports whether one was there to delete.
    pub fn delete_subscription(&self, id: Uuid) -> Result<bool> {
        Ok(self.store()?.delete_subscription(id)?)
    }

    /// Lists subscriptions with their next charge, soonest first.
    ///
    /// `from` is the day to reckon against - the frontend's own calendar
    /// day, since a billing date is a date on a calendar and only the
    /// frontend knows which one the person is looking at. Subscriptions
    /// renewing on the same day are ordered by name so the list does not
    /// shuffle between refreshes.
    pub fn renewals(&self, from: Date, include_archived: bool) -> Result<Vec<Renewal>> {
        let mut renewals = Vec::new();
        for sub in self.subscriptions(from, include_archived)? {
            let date = rondo_core::cycle::next_billing_date(
                sub.first_billing_date,
                BillingCycle::new(sub.cycle_count, sub.cycle_unit)?,
                from,
            )?;
            renewals.push(Renewal {
                subscription: sub,
                date,
            });
        }
        renewals.sort_by(|a, b| {
            a.date
                .cmp(&b.date)
                .then_with(|| a.subscription.name.cmp(&b.subscription.name))
        });
        Ok(renewals)
    }

    /// Serializes the whole database as readable JSON.
    ///
    /// The frontend decides where it goes; the core only produces the text.
    pub fn export_backup(&self) -> Result<String> {
        let store = self.store()?;
        Ok(rondo_core::backup::export_json(&store)?)
    }

    /// Restores a backup, merging it into what is already stored.
    ///
    /// Entries present in both are overwritten with the backed-up values
    /// and entries only here are left alone; nothing is deleted. Restoring
    /// the wrong file therefore cannot destroy data, and restoring the same
    /// file twice changes nothing the second time. A failure part-way
    /// leaves the database exactly as it was.
    pub fn import_backup(&self, json: String) -> Result<ImportSummary> {
        let store = self.store()?;
        Ok(rondo_core::backup::import_json(&store, &json)?.into())
    }

    /// Totals active spending, one entry per currency.
    ///
    /// Currencies are never mixed and archived subscriptions are left out.
    /// The totals carry full precision; rounding is the frontend's call,
    /// made once when the number is shown.
    ///
    /// Totalled at the prices in force on `on`, which is what "costs per
    /// month" means: a rise that takes effect next March is not part of
    /// this month's bill.
    pub fn spending_summary(&self, on: Date) -> Result<Vec<SpendingSummary>> {
        let subscriptions = self.store()?.subscriptions(None, on)?;
        Ok(rondo_core::summary::summarize(&subscriptions)
            .into_iter()
            .map(SpendingSummary::from)
            .collect())
    }

    /// What one subscription has cost from its first charge up to but not
    /// including `until`.
    ///
    /// Pass tomorrow for what has actually been charged so far. Every
    /// charge is counted at the price in force on its own day, so a
    /// subscription that rose in March is not retold as having always cost
    /// what it costs now.
    pub fn subscription_total(&self, id: Uuid, until: Date) -> Result<SubscriptionTotal> {
        let store = self.store()?;
        let sub = store
            .subscription(id, until)?
            .ok_or_else(|| RondoError::InvalidInput {
                message: format!("no subscription with id {id}"),
            })?;
        let history = store.price_history(id)?;
        Ok(rondo_core::summary::subscription_total(&sub, &history, until)?.into())
    }

    /// Month-by-month spending across `[from, to)`, one entry per month and
    /// currency.
    ///
    /// Each entry carries both readings: `charged` is what falls due that
    /// month, `levelled` spreads each subscription over its cycle. A chart
    /// of the first shows when money leaves; a chart of the second shows
    /// what is being spent. Months with nothing in them are present with
    /// zeros.
    ///
    /// Archived subscriptions are left out: Rondo does not record when one
    /// was archived, so it cannot say which months it belonged to.
    pub fn monthly_series(&self, from: Date, to: Date) -> Result<Vec<MonthlySpending>> {
        let store = self.store()?;
        let subs = store.subscriptions(None, from)?;
        let histories = store.all_price_histories()?;
        Ok(
            rondo_core::summary::monthly_series(&subs, &histories, from, to)?
                .into_iter()
                .map(MonthlySpending::from)
                .collect(),
        )
    }

    /// Levelled monthly cost per category and currency, largest first.
    ///
    /// Levelled because a share is about proportion: a yearly plan falling
    /// this month would otherwise swallow the chart.
    pub fn category_shares(&self, on: Date) -> Result<Vec<CategoryShare>> {
        let subs = self.store()?.subscriptions(None, on)?;
        Ok(rondo_core::summary::category_shares(&subs, on)
            .into_iter()
            .map(CategoryShare::from)
            .collect())
    }

    /// Totals every charge falling in `[from, to)`, per currency.
    ///
    /// Year to date is 1 January to tomorrow; all time starts at
    /// [`Self::earliest_charge`].
    pub fn window_totals(&self, from: Date, to: Date) -> Result<Vec<WindowTotal>> {
        let store = self.store()?;
        let subs = store.subscriptions(None, from)?;
        let histories = store.all_price_histories()?;
        Ok(
            rondo_core::summary::window_totals(&subs, &histories, from, to)?
                .into_iter()
                .map(WindowTotal::from)
                .collect(),
        )
    }

    /// The earliest day any active subscription was first charged, or
    /// nothing when there are none: where an all-time window starts.
    pub fn earliest_charge(&self, on: Date) -> Result<Option<Date>> {
        let subs = self.store()?.subscriptions(None, on)?;
        Ok(rondo_core::summary::earliest_charge(&subs))
    }

    /// Every price ever recorded for a subscription, earliest first.
    ///
    /// This is what anything summing charges over time must use: the single
    /// `amount` on a subscription is one day's reading, and a total built
    /// from it is wrong by every rise that ever happened.
    pub fn price_history(&self, subscription_id: Uuid) -> Result<Vec<Price>> {
        Ok(self
            .store()?
            .price_history(subscription_id)?
            .into_iter()
            .map(Price::from)
            .collect())
    }

    /// Records that the price changed from `effective_from`.
    ///
    /// The rise, not the correction: charges before that day keep the price
    /// they were charged at. Fixing a price that was typed wrong is
    /// [`Self::update_subscription`] or [`Self::correct_price`].
    pub fn add_price_change(
        &self,
        subscription_id: Uuid,
        amount: Decimal,
        currency: String,
        effective_from: Date,
    ) -> Result<Price> {
        Ok(self
            .store()?
            .add_price_change(
                subscription_id,
                Money::new(amount, &currency)?,
                effective_from,
            )?
            .into())
    }

    /// Overwrites one price entry, for when it was recorded wrong.
    pub fn correct_price(&self, price: Price) -> Result<Price> {
        let price = rondo_core::model::Price::try_from(price)?;
        Ok(self.store()?.correct_price(&price)?.into())
    }

    /// Removes one price entry; reports whether one was there.
    ///
    /// Refuses to remove the last, which would leave a subscription with no
    /// price at all.
    pub fn delete_price(&self, id: Uuid) -> Result<bool> {
        Ok(self.store()?.delete_price(id)?)
    }

    /// Lists payment methods in the order the person arranged them.
    pub fn payment_methods(&self) -> Result<Vec<PaymentMethod>> {
        Ok(self
            .store()?
            .payment_methods()?
            .into_iter()
            .map(PaymentMethod::from)
            .collect())
    }

    /// Records a new payment method and returns it as stored.
    pub fn add_payment_method(&self, name: String, sort_order: i32) -> Result<PaymentMethod> {
        let method = rondo_core::model::PaymentMethod::new(&name, sort_order)?;
        self.store()?.insert_payment_method(&method)?;
        Ok(method.into())
    }

    /// Saves an edited payment method, renaming it everywhere it is used.
    pub fn update_payment_method(&self, method: PaymentMethod) -> Result<PaymentMethod> {
        let method = rondo_core::model::PaymentMethod::from(method);
        Ok(self.store()?.update_payment_method(&method)?.into())
    }

    /// Deletes a payment method; subscriptions paying by it keep existing
    /// with none. Reports whether one was there to delete.
    pub fn delete_payment_method(&self, id: Uuid) -> Result<bool> {
        Ok(self.store()?.delete_payment_method(id)?)
    }

    /// Lists categories in the order the person arranged them.
    pub fn categories(&self) -> Result<Vec<Category>> {
        Ok(self
            .store()?
            .categories()?
            .into_iter()
            .map(Category::from)
            .collect())
    }

    /// Creates a category and returns it with its assigned id.
    pub fn add_category(&self, name: String, sort_order: i32) -> Result<Category> {
        let category = CoreCategory::new(&name, sort_order)?;
        self.store()?.insert_category(&category)?;
        Ok(category.into())
    }

    /// Saves a renamed or reordered category.
    pub fn update_category(&self, category: Category) -> Result<()> {
        Ok(self.store()?.update_category(&category.into())?)
    }

    /// Deletes a category; reports whether one was there to delete.
    ///
    /// Subscriptions filed under it are kept and simply lose the
    /// assignment, so deleting a grouping never deletes what it grouped.
    pub fn delete_category(&self, id: Uuid) -> Result<bool> {
        Ok(self.store()?.delete_category(id)?)
    }

    /// Moves a subscription into or out of the archive.
    ///
    /// Archiving keeps the record and its history but drops it from the
    /// active list and from spending totals.
    pub fn set_archived(&self, id: Uuid, archived: bool, on: Date) -> Result<Subscription> {
        let store = self.store()?;
        let mut sub = store
            .subscription(id, on)?
            .ok_or_else(|| RondoError::InvalidInput {
                message: format!("no subscription with id {id}"),
            })?;
        sub.status = if archived {
            SubscriptionStatus::Archived
        } else {
            SubscriptionStatus::Active
        };
        Ok(store.update_subscription(&sub, on)?.into())
    }
}

impl Rondo {
    /// Borrows the store, turning a poisoned lock into a reportable error.
    ///
    /// Poisoning means an earlier call panicked mid-operation, so the
    /// database may hold a half-finished change. Refusing to continue is
    /// safer than handing out a guard as though nothing happened.
    fn store(&self) -> Result<MutexGuard<'_, Store>> {
        self.store.lock().map_err(|_| RondoError::Storage {
            message: "the database was left in an unknown state by an earlier failure".into(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rondo_core::model::CycleUnit;
    use std::str::FromStr;

    /// The day these tests read prices as of, standing in for the calendar
    /// day a frontend would pass. Later than every draft's first charge.
    const TODAY: Date = Date::constant(2026, 6, 1);

    fn draft(name: &str) -> NewSubscription {
        NewSubscription {
            name: name.to_owned(),
            amount: Decimal::from_str("15.90").unwrap(),
            currency: "USD".into(),
            cycle_count: 1,
            cycle_unit: CycleUnit::Month,
            first_billing_date: Date::constant(2026, 1, 31),
            notes: None,
            template_id: None,
            category_id: None,
            reminder_lead_days: None,
        }
    }

    fn open() -> Arc<Rondo> {
        Rondo::open_in_memory().unwrap()
    }

    #[test]
    fn a_subscription_can_be_added_and_read_back() {
        let rondo = open();
        let added = rondo.add_subscription(draft("Netflix")).unwrap();
        assert_eq!(added.name, "Netflix");
        assert_eq!(added.amount.to_string(), "15.90");

        let loaded = rondo.subscription(added.id, TODAY).unwrap().unwrap();
        assert_eq!(loaded, added);
        assert_eq!(rondo.subscriptions(TODAY, false).unwrap(), vec![added]);
    }

    #[test]
    fn an_unknown_id_reads_as_nothing_rather_than_failing() {
        let rondo = open();
        assert!(rondo.subscription(Uuid::now_v7(), TODAY).unwrap().is_none());
        assert!(!rondo.delete_subscription(Uuid::now_v7()).unwrap());
    }

    #[test]
    fn a_rejected_draft_never_reaches_the_database() {
        let rondo = open();
        let mut bad = draft("Netflix");
        bad.currency = "dollars".into();
        assert!(matches!(
            rondo.add_subscription(bad),
            Err(RondoError::InvalidInput { .. })
        ));
        assert!(rondo.subscriptions(TODAY, true).unwrap().is_empty());
    }

    #[test]
    fn editing_returns_the_stored_value_with_a_new_timestamp() {
        let rondo = open();
        let mut sub = rondo.add_subscription(draft("Netflix")).unwrap();
        sub.name = "Netflix Premium".into();
        let saved = rondo.update_subscription(sub.clone(), TODAY).unwrap();

        assert_eq!(saved.name, "Netflix Premium");
        assert!(saved.updated_at >= sub.updated_at);
        assert_eq!(rondo.subscription(sub.id, TODAY).unwrap().unwrap(), saved);
    }

    #[test]
    fn archiving_hides_a_subscription_without_deleting_it() {
        let rondo = open();
        let sub = rondo.add_subscription(draft("Netflix")).unwrap();

        rondo.set_archived(sub.id, true, TODAY).unwrap();
        assert!(rondo.subscriptions(TODAY, false).unwrap().is_empty());
        assert_eq!(rondo.subscriptions(TODAY, true).unwrap().len(), 1);

        rondo.set_archived(sub.id, false, TODAY).unwrap();
        assert_eq!(rondo.subscriptions(TODAY, false).unwrap().len(), 1);
    }

    #[test]
    fn renewals_come_back_soonest_first() {
        let rondo = open();
        let mut monthly = draft("Monthly");
        monthly.first_billing_date = Date::constant(2026, 8, 5);
        let mut yearly = draft("Yearly");
        yearly.cycle_unit = CycleUnit::Year;
        yearly.first_billing_date = Date::constant(2026, 3, 15);
        rondo.add_subscription(yearly).unwrap();
        rondo.add_subscription(monthly).unwrap();

        let from = Date::constant(2026, 8, 21);
        let renewals = rondo.renewals(from, false).unwrap();
        assert_eq!(
            renewals
                .iter()
                .map(|r| (r.subscription.name.as_str(), r.date.to_string()))
                .collect::<Vec<_>>(),
            vec![
                ("Monthly", "2026-09-05".into()),
                ("Yearly", "2027-03-15".into())
            ]
        );
    }

    #[test]
    fn a_renewal_date_stays_anchored_across_a_short_month() {
        let rondo = open();
        // First charged on the 31st, so February clamps but March does not.
        let sub = rondo.add_subscription(draft("Netflix")).unwrap();
        assert_eq!(sub.first_billing_date.to_string(), "2026-01-31");

        let february = rondo.renewals(Date::constant(2026, 2, 1), false).unwrap();
        assert_eq!(february[0].date.to_string(), "2026-02-28");

        let march = rondo.renewals(Date::constant(2026, 3, 1), false).unwrap();
        assert_eq!(march[0].date.to_string(), "2026-03-31");
    }

    #[test]
    fn renewals_on_the_same_day_keep_a_stable_order() {
        let rondo = open();
        for name in ["Zulu", "Alpha"] {
            rondo.add_subscription(draft(name)).unwrap();
        }
        let renewals = rondo.renewals(Date::constant(2026, 1, 1), false).unwrap();
        let names: Vec<&str> = renewals
            .iter()
            .map(|r| r.subscription.name.as_str())
            .collect();
        assert_eq!(names, vec!["Alpha", "Zulu"]);
    }

    #[test]
    fn categories_can_be_created_renamed_and_removed() {
        let rondo = open();
        let mut streaming = rondo.add_category("Streaming".into(), 0).unwrap();
        rondo.add_category("Tools".into(), 1).unwrap();

        streaming.name = "Screens".into();
        rondo.update_category(streaming.clone()).unwrap();
        // Only the two this test made: every database is seeded with the
        // built-in categories, which sort after these and are not the
        // subject here.
        let names: Vec<String> = rondo
            .categories()
            .unwrap()
            .into_iter()
            .filter(|c| !c.id.to_string().starts_with("00000000-0000-7000-8000-"))
            .map(|c| c.name)
            .collect();
        assert_eq!(names, vec!["Screens", "Tools"]);

        assert!(rondo.delete_category(streaming.id).unwrap());
        assert!(!rondo.delete_category(streaming.id).unwrap());
    }

    #[test]
    fn deleting_a_category_keeps_what_it_grouped() {
        let rondo = open();
        let category = rondo.add_category("Streaming".into(), 0).unwrap();
        let mut with_category = draft("Netflix");
        with_category.category_id = Some(category.id);
        let sub = rondo.add_subscription(with_category).unwrap();

        rondo.delete_category(category.id).unwrap();
        let reloaded = rondo.subscription(sub.id, TODAY).unwrap().unwrap();
        assert_eq!(reloaded.category_id, None);
    }

    #[test]
    fn a_category_needs_a_name() {
        let rondo = open();
        assert!(matches!(
            rondo.add_category("   ".into(), 0),
            Err(RondoError::InvalidInput { .. })
        ));
    }

    #[test]
    fn spending_totals_stay_separate_per_currency_and_skip_archived() {
        let rondo = open();
        // 15.90 monthly and 120 yearly in USD, plus 8 monthly in CNY.
        rondo.add_subscription(draft("Netflix")).unwrap();
        let mut yearly = draft("Copilot");
        yearly.amount = Decimal::from_str("120").unwrap();
        yearly.cycle_unit = CycleUnit::Year;
        rondo.add_subscription(yearly).unwrap();
        let mut cny = draft("Music");
        cny.amount = Decimal::from_str("8").unwrap();
        cny.currency = "CNY".into();
        rondo.add_subscription(cny).unwrap();
        let archived = rondo.add_subscription(draft("Gone")).unwrap();
        rondo.set_archived(archived.id, true, TODAY).unwrap();

        let summary = rondo.spending_summary(TODAY).unwrap();
        assert_eq!(summary.len(), 2, "currencies are never mixed");
        let cny = &summary[0];
        assert_eq!(cny.currency, "CNY");
        assert_eq!(cny.monthly.to_string(), "8");
        let usd = &summary[1];
        assert_eq!(usd.currency, "USD");
        assert_eq!(usd.subscription_count, 2, "the archived one is left out");
        // 15.90 a month plus 120 a year is 25.90 a month.
        assert_eq!(usd.monthly.to_string(), "25.90");
    }

    /// The arithmetic is the core's and tested there. What this holds down
    /// is that the store's own subscriptions and histories reach it, and
    /// that a rise recorded through this object is the one the totals use.
    #[test]
    fn the_aggregations_see_a_rise_recorded_through_the_bridge() {
        let rondo = open();
        let mut monthly = draft("Netflix");
        monthly.first_billing_date = Date::constant(2026, 1, 1);
        let added = rondo.add_subscription(monthly).unwrap();
        rondo
            .add_price_change(
                added.id,
                Decimal::from_str("15.00").unwrap(),
                "USD".into(),
                Date::constant(2026, 3, 1),
            )
            .unwrap();

        // Two charges at 15.90 and two at 15.00 across January to April.
        let total = rondo
            .subscription_total(added.id, Date::constant(2026, 5, 1))
            .unwrap();
        assert_eq!(total.charge_count, 4);
        assert_eq!(total.total, Decimal::from_str("61.80").unwrap());
        assert_eq!(total.first_charge, Some(Date::constant(2026, 1, 1)));

        let series = rondo
            .monthly_series(Date::constant(2026, 1, 1), Date::constant(2026, 5, 1))
            .unwrap();
        assert_eq!(series.len(), 4);
        assert_eq!(series[2].charged, Decimal::from_str("15.00").unwrap());

        // The two views must agree, across the boundary as well as inside.
        let window = rondo
            .window_totals(Date::constant(2026, 1, 1), Date::constant(2026, 5, 1))
            .unwrap();
        assert_eq!(window[0].total, total.total);
        assert_eq!(
            series.iter().map(|m| m.charged).sum::<Decimal>(),
            window[0].total
        );

        let shares = rondo.category_shares(Date::constant(2026, 5, 1)).unwrap();
        assert_eq!(shares.len(), 1);
        assert_eq!(shares[0].category_id, None, "uncategorized is a share");
        assert_eq!(
            rondo.earliest_charge(Date::constant(2026, 5, 1)).unwrap(),
            Some(Date::constant(2026, 1, 1))
        );
    }

    #[test]
    fn the_template_catalogue_is_available_without_a_database() {
        let templates = crate::records::service_templates();
        assert!(!templates.is_empty());
        assert!(templates.iter().any(|t| t.name == "Netflix"));
        assert!(templates.iter().all(|t| !t.default_category.is_empty()));
    }

    /// The ranking itself is the core's, and tested there. What this holds
    /// down is that the query survives the crossing at all - a bridge that
    /// dropped it would still return a plausible list.
    #[test]
    fn searching_the_catalogue_crosses_the_bridge() {
        let hits = crate::records::search_service_templates("B站".into());
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].name, "Bilibili 大会员");

        let all = crate::records::search_service_templates(String::new());
        assert_eq!(all.len(), crate::records::service_templates().len());
    }

    #[test]
    fn the_custom_id_is_not_a_bundled_service() {
        let custom = crate::records::custom_template_id();
        assert!(!custom.is_empty());
        assert!(
            crate::records::service_templates()
                .iter()
                .all(|t| t.id != custom)
        );
    }

    #[test]
    fn a_backup_carries_a_database_to_another_one() {
        let source = open();
        let category = source.add_category("Streaming".into(), 0).unwrap();
        let mut filed = draft("Netflix");
        filed.category_id = Some(category.id);
        let sub = source.add_subscription(filed).unwrap();
        let json = source.export_backup().unwrap();

        let target = open();
        let summary = target.import_backup(json.clone()).unwrap();
        assert_eq!(summary.categories_added, 1);
        assert_eq!(summary.subscriptions_added, 1);
        // Every field survives, timestamps included.
        assert_eq!(target.subscription(sub.id, TODAY).unwrap().unwrap(), sub);

        // Restoring the same file again changes nothing.
        let again = target.import_backup(json).unwrap();
        assert_eq!(again.subscriptions_added, 0);
        assert_eq!(again.subscriptions_updated, 1);
        assert_eq!(target.subscriptions(TODAY, true).unwrap().len(), 1);
    }

    #[test]
    fn restoring_a_bad_file_leaves_the_database_untouched() {
        let rondo = open();
        let kept = rondo.add_subscription(draft("Netflix")).unwrap();

        assert!(matches!(
            rondo.import_backup("not json".into()),
            Err(RondoError::UnusableData { .. })
        ));
        assert_eq!(rondo.subscriptions(TODAY, true).unwrap(), vec![kept]);
    }

    #[test]
    fn archiving_an_unknown_id_says_so() {
        let rondo = open();
        assert!(matches!(
            rondo.set_archived(Uuid::now_v7(), true, TODAY),
            Err(RondoError::InvalidInput { .. })
        ));
    }
}
