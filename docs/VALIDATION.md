# Validation

How the scorecard's findings were checked. Two parts: (A) a **cross-source
de-peg confirmation** that anyone can reproduce, and (B) a **lead-time study**
that characterises how much warning the de-peg axis gives — reported with its
limits, and explicitly labelled as a separate off-chain study, not output of the
query in this repo.

All figures below are from the snapshot dated **2026-06-23**; numbers drift as the
query re-runs on fresh data.

## A. Cross-source de-peg confirmation (reproducible)

Each trap the scorecard flags was confirmed **independently** against an off-chain
price source (DefiLlama `coins.llama.fi` price history) — i.e. the de-peg is not an
artifact of the Dune `dex.trades` reconstruction. Both sources show the same
asset holding its peg for months and then breaking to the same level.

| asset | chain | address | held peg until | break | level now | sources agree |
|---|---|---|---|---|---|---|
| msUSD  | ethereum | `0x4ba0…7c00` | 2026-06-20 (~$1.000, 11 mo) | **−62.6% in 1 day** (06-21) | ~$0.25 | DefiLlama $0.262 · Dune median $0.250 |
| apxUSD | ethereum | `0x98a8…4665` | ~late May 2026 (~$1.00) | gradual from ~05-29 | ~$0.89 | DefiLlama ~$0.89 · Dune median $0.892 |
| sUSDat | ethereum | `0xd166…2df7` | ~2 months at ~$1.00 | step to ~$0.90 | ~$0.90 | DefiLlama · Dune median $0.904 |
| apyUSD | ethereum | `0x38ee…8a6a` | — | sitting below NAV | depeg ≈ −10.7% | DefiLlama · Dune |

`msUSD` is the cleanest illustration of the **sudden** sub-type: rock-solid at
`$0.999–1.000` through 2026-06-20, then `0.9994 → 0.3737` on 2026-06-21. There was
no prior drift — a live read would have flagged it `BROKEN` *after* the break, not
before. This is exactly why the headline claim is "descriptive, not predictive".

### Reproduce it yourself

1. **Current state** — run [`queries/yield_real_scorecard.sql`](../queries/yield_real_scorecard.sql)
   on Dune; read the `depeg_now_pct` / `stato` columns.
2. **Price history (independent)** — for any address above, fetch
   `https://coins.llama.fi/chart/ethereum:<address>?span=400&period=1d` and confirm
   the held-peg period and the break date.

## B. Lead-time study (reproducible; off-chain, separate from the Dune query)

**Question:** when a de-peg *is* gradual, how much warning would the de-peg axis
have given? **Method (no look-ahead):** over a universe of 269 underlyings
([`validation/lead_time_tokens.json`](../validation/lead_time_tokens.json)), take
each asset's DefiLlama daily price, de-spike it, compute the causal de-peg
(price ÷ running-max NAV, or ÷ $1 for stables), keep the **severe** ones (trough
< −5%), apply the **same scope gate as the scorecard** (peg-class only — never-
pegged volatile tokens excluded), **de-duplicate to distinct underlyings**, and
measure the days from the first causal −2% reading to the trough.

**Result (snapshot 2026-06-23):** **12 distinct severe de-peg episodes**;
**median lead time 30 days**, mean 57; **9/12 (75%) ≥ 14 days**, 10/12 (83%) ≥ 7
days; 1/12 flagged sudden. Frozen event list:
[`validation/lead_time_events_2026-06-23.csv`](../validation/lead_time_events_2026-06-23.csv);
provenance + hashes in
[`validation/source_manifest_2026-06-23.json`](../validation/source_manifest_2026-06-23.json).

> **Why this is smaller than it first looked.** An earlier internal count put this
> at "33 events". Building this reproducible script showed that figure was
> inflated ~2.7×: it (a) counted never-pegged volatile tokens (e.g. a CRV
> derivative at −78%) as de-pegs, and (b) double-counted the same underlying
> across several token contracts. The scope gate and de-dup above remove both. The
> honest, reproducible number is **12**.

**Limits — read these with the result:**

- **Sudden breaks are under-counted.** The de-spike filter (which removes data
  glitches) also masks a de-peg that lands in a *single* day — so `msUSD`
  (−62% on 2026-06-21, part A) is **not** in this set. The study therefore
  characterises **gradual** de-pegs, exactly the population for which a lead time
  is meaningful; it is not a base rate of all breaks.
- The −2% reading is causal and actionable; the **trough is retrospective**, so
  the figure measures the *duration of the slide*, not the timing of the minimum.
- **n = 12** is a modest sample; treat the median as indicative, not precise.
- This study uses **off-chain** price history and is **not** produced by the Dune
  query — it is reported here so the "descriptive, with lead time on gradual
  cases" framing is auditable rather than asserted.

### Reproduce it yourself

```
python scripts/fetch_defillama_price_history.py \
    --config validation/lead_time_tokens.json --out validation/price_history.csv --span 400
python scripts/run_lead_time_study.py \
    --prices validation/price_history.csv --config validation/lead_time_tokens.json \
    --out validation/lead_time_events.csv
```

Compare your `lead_time_events.csv` to the frozen
`validation/lead_time_events_2026-06-23.csv`. Small drift is expected as DefiLlama
backfills/updates its price history.

## C. What is and isn't validated

- **Validated:** that the flagged de-pegs are real (cross-source) and material;
  that for gradual cases the slide precedes the bottom with the lead time above.
- **Not claimed:** advance warning for sudden breaks; a redemption-accurate NAV;
  coverage of assets that do not trade enough to be priced from `dex.trades`.
