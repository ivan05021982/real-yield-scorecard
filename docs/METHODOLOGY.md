# Methodology

This document specifies exactly how the scorecard is computed, why each
threshold is what it is, and how the result was validated. The guiding principle
is that every number be either an observable or justified by the data — no
hand-tuned magic constants.

## 1. Data source and price reconstruction

Dune's curated price oracle (`prices.usd`) covers blue-chip tokens only; the
exotic Pendle underlyings — exactly where the traps are — are absent. Because
those tokens still *trade* on DEXes (that is how off-chain aggregators price
them), their USD price is recovered from `dex.trades`:

```
implied price of a trade = amount_usd / (underlying token amount in the trade)
```

`amount_usd` is denominated via the trade's *other* side (USDC / WETH / …), which
Dune prices well, so the implied price is a real, executable USD price of the
underlying — not a mid-oracle quote. The **same scan** yields traded **volume**
(the exit-liquidity axis).

## 2. De-peg axis

For each `(token, chain)`:

- **Daily price** = `median` of per-trade implied prices that day (robust to
  single fat prints), kept only for days with **≥ 5 qualifying trades**.
- **Asset class** = *yield-bearing* if the token's median price `> 1.03`, else
  *stable*.
- **Causal NAV reference** =
  - stables → `1.0`;
  - yield-bearing → **running maximum** of the daily price (a causal, no-look-
    ahead proxy for the accruing NAV).
- **De-peg now** = `last price / NAV − 1`.

The running-max proxy is deliberately simple and causal. It is *not* the on-chain
`convertToAssets()` redemption value (which would need an archive node): it is
**adequate for a descriptive screen, not a redemption guarantee**. It is also a
**windowed** running max — taken over the query's trailing window (180 days by
default, set by the `dex.trades` time filter), not all-time — so for a token whose
high predates the window the de-peg is, if anything, understated. Both points are
stated openly rather than dressed up as a true NAV.

## 3. Exit-liquidity axis

Two trailing windows of traded USD volume per `(token, chain)`:

- `exit_liq_14d` = Σ volume over the last 14 days;
- `vol_prev_14d` = Σ volume over the 14 days before that;
- `liq_chg_pct` = their ratio − 1.

A collapsing `liq_chg_pct` *during* a deepening de-peg is the "exit door that
closes" — the liquidity to get out evaporates exactly when you need it.

## 4. Robustness gates

Raw on-chain trade data is noisy; without guards a single bad trade poisons the
price, the volatility estimate and (worst) the running-max NAV, producing both
false positives and false negatives. The gates:

| Gate | Rule | Why |
|---|---|---|
| Trade filter | keep `$100 ≤ amount_usd ≤ $5M` | drop dust and fat-finger/errored prints |
| Robust price | per-day **median**, ≥ 5 trades | one print cannot move the day |
| Volatility | **median \|daily log-return\|** | MAD-style; see §5 |
| Liquidity floor | assert `BROKEN`/`WATCH` only if 14d volume ≥ `$100k` | a de-peg on trivial volume is noise, not a trap |

## 5. Scope gate (which assets the de-peg axis applies to)

The de-peg axis is only meaningful for **peg-class** assets. Two exclusions:

- **Non-USD reference** (e.g. ETH/BTC-denominated such as LSTs) — median price
  outside `[0.3, 3.0]`. A wstETH falling with ETH is not a de-peg. (Labelled
  `~ non-USD-reference / out-of-scope`.)
- **Volatile (never-pegged)** — robust daily volatility above threshold. A
  governance/reward token (e.g. a CRV derivative) that simply drifts down is
  market risk, not a broken peg; scoring it as a `−70%` "de-peg" would be a
  category error.

The volatility measure is the **median absolute daily log-return**, *not* the
standard deviation. This is the crux: a peg that stays calm and then breaks keeps
a tiny *median* |return| (most days are calm) even though its *stdev* is inflated
by the break — so a real-but-broken trap is **not** mistaken for a never-pegged
volatile token. On the validation corpus the separation is wide and clean:

- every peg-class asset — *including the ones that later broke* — has at least
  one calm stretch around `≤ 0.05%/day`;
- a never-pegged token (CRV) never calms below `~1.1%/day`.

The `1.2%` cut is applied to the **windowed** median |return| — computed over the
query's trailing window (180 days by default), not over all history — and sits
comfortably between the two. It is set by the observed gap, not chosen to fit a
desired answer.

## 6. Classification

In honest gating order (structural scope first, then assertion):

```
non-USD-reference / out-of-scope  ←  if median price ∉ [0.3, 3.0]
volatile (market risk)            ←  if robust vol > 1.2%
thin/illiquid                     ←  if de-peg < −1.5% and 14d volume < $100k
BROKEN                            ←  if de-peg < −8%
WATCH                             ←  if de-peg < −1.5%
healthy                           ←  otherwise
```

## 7. Validation

- **Cross-source agreement.** The de-pegs the scorecard surfaces were confirmed
  independently against an off-chain price source (DefiLlama): the same assets
  held `$1` for months and then broke to the same levels.
- **Materiality.** On the validation snapshot the traps are real and material,
  not a curiosity — assets advertising `+8%` to `+25%` APY whose underlying sat
  `−9%` to `−75%` below NAV, several with exit liquidity already collapsing
  `60–95%`.
- **Lead time, honestly.** On a reproducible study of gradual de-pegs (12 distinct
  episodes — see [VALIDATION.md](VALIDATION.md)), the slide precedes the bottom by a
  **median of 30 days** (9/12 ≥ 14 days), so a live read would have flagged `WATCH`
  well before the worst. *Sudden* breaks give no lead time — one asset broke `−62%`
  in a single day — and are under-counted by the study's de-spike, so this is a
  statement about gradual cases, not a base rate of all breaks. The scorecard
  reports realized state; it does not claim to predict.

## 8. What this is not

It is not a yield-safety oracle, a redemption-value feed, or a forecast. It is a
transparent, forkable recomputation of *realized* real yield and exit liquidity
from public on-chain trades, meant to be inspected and forked, not trusted
blindly.
