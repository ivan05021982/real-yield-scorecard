# Real-Yield Scorecard

> **Descriptive, not predictive.** This scorecard reports the *realized* on-chain
> state of each underlying — where it trades now relative to its NAV, and whether
> its exit liquidity is intact or evaporating. It does **not** forecast future
> de-pegs (see [What it is — and what it is not](#what-it-is--and-what-it-is-not)).

A **forkable, Dune-native** scorecard that recomputes Pendle underlyings' real yield
from on-chain data — putting the *advertised* APY next to two things it hides:

1. **De-peg of the underlying** — how far the underlying token currently trades
   *below* its causal NAV reference (running-max for yield-bearing tokens, `$1`
   for stables). A high APY on a `–10%` underlying is not a high yield.
2. **Exit liquidity** — traded USD volume over the last 14 days vs the prior 14
   days. A de-peg you can exit at a small loss is very different from one where
   the door is closing as you reach for it.

Both axes are reconstructed from a **single `dex.trades` scan** — no curated price
oracle is required, which matters because the exotic underlyings where the traps
live are *not* in Dune's `prices.usd`. Their USD price is recovered from each
trade's `amount_usd` (whose quote side is a blue-chip token Dune prices well).

> The advertised APY is intentionally **not** computed here. It is the number
> being checked, and it belongs to the off-chain aggregator (Pendle / DefiLlama).

Chains: **Ethereum, Arbitrum, Base, BNB** (the chains among Pendle's deployments
that Dune's `dex.trades` indexes).

---

## What it is — and what it is not

**It is** a descriptive, point-in-time read of *realized* on-chain reality:
where an underlying trades now relative to where it should, and whether its exit
liquidity is intact or evaporating.

**It is not** a prediction of future de-pegs. Some de-pegs unfold gradually and
the scorecard would have shown the slide for days or weeks before the bottom;
others are sudden — e.g. a stablecoin in the validation set broke **−62% in a
single day** with no prior drift. The scorecard distinguishes *"avoid now"* from
*"exit, with lead time"*; it does not promise advance warning in every case.

## Honest limitations

- **Coverage** is whatever Dune's `dex.trades` indexes. Days with fewer than 5
  qualifying trades are dropped — a token that barely trades cannot be priced
  from its trades, and the scorecard says so (`thin/illiquid`) rather than
  guessing.
- **Price** is the robust **median of on-chain trade prices** per day, not an
  oracle. For yield-bearing tokens the causal NAV is a **running-max proxy**, not
  the on-chain `convertToAssets()` redemption value — adequate for a descriptive
  screen, not a redemption guarantee.
- **The NAV reference is windowed.** The running max is taken over the query's
  trailing window (180 days by default), not all-time; for a token whose high
  predates the window the de-peg is, if anything, understated.
- **Scope gate.** The de-peg axis only applies to *peg-class* underlyings.
  Never-pegged volatile tokens (e.g. governance/reward tokens) and ETH/BTC-
  denominated assets are flagged out-of-scope, not scored as de-pegs — a falling
  governance token is market risk, not a broken peg.
- **Single-chain reads can diverge.** The same asset is scored independently per
  chain; a token can read broken on one chain and healthy on another.

## How it works

```
dex.trades  ──►  per-day robust median price + traded volume   (per token, per chain)
            │
            ├──►  de-peg  = price / causal-NAV − 1
            └──►  exit-liq = Σ volume (last 14d)  vs  Σ volume (prior 14d)
```

Robustness (raw DEX VWAP is too noisy to ship — one bad print poisons price, vol
and the NAV):

- trade-level guards drop dust (`< $100`) and fat-finger prints (`> $5M`);
- the daily price is a **median**, with a **≥ 5-trade floor**;
- the volatility gate uses the **median absolute daily log-return** (MAD-style,
  not standard deviation), so a real-but-broken peg is not mistaken for a
  never-pegged volatile token;
- a **liquidity floor** is required before any `BROKEN` / `WATCH` is asserted —
  a `−12%` reading on a few thousand dollars of volume is noise, not a trap.

## Fork it

1. Open [`queries/yield_real_scorecard.sql`](queries/yield_real_scorecard.sql) on
   Dune and run it as-is, **or**
2. edit the `tokens (symbol, blockchain, address)` `VALUES` list to your own
   universe and re-run. Everything downstream adapts.

See [`docs/METHODOLOGY.md`](docs/METHODOLOGY.md) for the full method and the
classification rules, [`docs/VALIDATION.md`](docs/VALIDATION.md) for how the
findings were checked, and [`examples/`](examples/) for snapshots — both the raw
query output and an off-chain-enriched version (the [examples note](examples/README.md)
explains which columns come from the query and which are off-chain).

## Reproducible validation

The de-peg confirmation and the lead-time study are both reproducible. The
lead-time study ships as runnable scripts plus a frozen, hashed result:

- [`scripts/fetch_defillama_price_history.py`](scripts/fetch_defillama_price_history.py) → price history
- [`scripts/run_lead_time_study.py`](scripts/run_lead_time_study.py) → the event list + stats
- [`validation/`](validation/) → the token universe, the frozen events, and a
  source manifest (URLs, hashes). See [`docs/VALIDATION.md`](docs/VALIDATION.md)
  for the exact commands. `pip install -r requirements.txt`.

## License

MIT — see [`LICENSE`](LICENSE).
