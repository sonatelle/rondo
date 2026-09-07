-- Exchange rates, stored as a history rather than as today's numbers.
--
-- A charge is converted at the rate of its own day, exactly as it is priced
-- at the price entry in force on its own day. Keeping only current rates
-- would make every past total move whenever the market did, so last
-- month's spending would read differently tomorrow than it does today.
--
-- Every rate is quoted against one fixed base, EUR, and says how many units
-- of `currency` one unit of the base bought that day. Converting X to Y
-- goes through the base: amount / rate(X) * rate(Y). The base is fixed
-- rather than set to whichever currency the person totals in, because
-- changing that setting would otherwise invalidate every stored row and
-- mean fetching the whole history again. The base itself is never stored;
-- it is 1 by definition, and the conversion code knows that.

CREATE TABLE exchange_rate (
    -- Three-letter uppercase code, as everywhere else money is stored.
    currency     TEXT NOT NULL,
    -- The civil date this rate was published for. It stands for every day
    -- from here until the next entry: sources publish on the days they
    -- publish, and a charge falling on a skipped day still needs a rate.
    effective_on TEXT NOT NULL,
    -- Units of `currency` per one unit of the base, as an exact decimal.
    rate         TEXT NOT NULL,
    -- 1 when a person typed this rate in. A fetch never overwrites one of
    -- these: somebody who corrected a rate by hand meant it, and having it
    -- silently replaced on the next refresh would be the bug.
    is_manual    INTEGER NOT NULL,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL,
    -- No surrogate id, unlike every other table here. A rate is not a thing
    -- somebody names or reorders; it is a fact about a currency on a day,
    -- and that pair is its identity. Making it the primary key is also what
    -- makes "one rate per currency per day" impossible to violate, and it
    -- is the index the only lookup there is wants: the latest row for one
    -- currency at or before some day.
    PRIMARY KEY (currency, effective_on)
) STRICT;
