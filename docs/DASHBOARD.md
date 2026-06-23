# Dune Dashboard — build spec

The dashboard is powered by the single forkable query
[`queries/yield_real_scorecard.sql`](../queries/yield_real_scorecard.sql). Save
that query on Dune once, then attach the visualizations below to it. Everything
except the advertised-APY callout is Dune-native and refreshes on its own.

## Title & framing (text widget, top)

> **Real-Yield Scorecard — what the APY hides**
> For each Pendle underlying (Ethereum · Arbitrum · Base · BNB), the on-chain
> reality next to the advertised yield: how far the underlying sits below its
> NAV, and whether the exit door is still open. Descriptive, not predictive —
> see methodology. Fork this query and swap in your own token list.

## Visualizations (all from the one query)

1. **Counters** (one row of big-number tiles)
   - `BROKEN`  = count where `stato = 'BROKEN'`
   - `WATCH`   = count where `stato = 'WATCH'`
   - `healthy` = count where `stato = 'healthy'`
   - `out-of-scope / thin` = the rest
   *(Add a tiny `COUNT` wrapper query per tile, or use Dune counter on a filtered
   table.)*

2. **Traps table** — *the headline.* Filter `stato IN ('BROKEN','WATCH')`,
   columns: `symbol, chain, depeg_now_pct, exit_liq_14d, liq_chg_pct, stato`.
   Conditional formatting: red on `depeg_now_pct`, red on negative `liq_chg_pct`.

3. **"The exit door closes" — bar chart.** For the flagged tokens, plot
   `liq_chg_pct` (14d volume vs prior 14d). The deepest de-pegs sitting next to
   the steepest liquidity drops is the whole story in one picture.

4. **De-peg vs exit-liquidity — scatter.** X = `depeg_now_pct`, Y =
   `log(exit_liq_14d)`, color = `stato`. Separates the two trap profiles: deep
   de-peg **and** illiquid (you are stuck) vs deep de-peg but still liquid (you
   exit at a loss).

5. **Full scorecard table** — the complete query output, sortable, for readers
   who want every row including the healthy and out-of-scope assets (showing the
   healthy ones is part of the honesty: the method is not a red-flag generator).

## Advertised-APY callout (text widget)

Dune does not carry Pendle's advertised APY, so the "+X% advertised → reality"
comparison is shown as a static, dated callout sourced from Pendle/DefiLlama
(see [`examples/`](../examples/)). Keep it dated and labelled as off-chain, e.g.:

> Snapshot 2026-06-23 — advertised vs reality: `apxUSD +9% → −11% & exit liq −83%`,
> `apyUSD +25% → only $0.7M exit liq, −69%`, `msUSD +8% → −75%`.

## Honesty footer (text widget, bottom)

> Robust median on-chain prices, causal running-max NAV proxy (not redemption
> value), de-peg axis gated to peg-class assets only. Thinly-traded days are
> dropped. Sudden breaks give no lead time. Method & limits: README + METHODOLOGY.

## Optional: saving the query via API

The query can be created/updated programmatically via Dune's query CRUD API
(`POST /api/v1/query`), but that endpoint requires a paid Dune plan. On the free
plan, paste the SQL into a new query in the Dune UI instead. The dashboard layout
itself is assembled in the UI either way.
