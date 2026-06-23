# Example snapshots (2026-06-23)

Two files, to keep the line between on-chain output and off-chain enrichment
explicit:

## `query_output_2026-06-23.csv` — raw query output

Exactly the columns [`queries/yield_real_scorecard.sql`](../queries/yield_real_scorecard.sql)
produces, nothing added:

`symbol, chain, med_price, realized_vol_pct, last_price, nav_ref, depeg_now_pct,
exit_liq_14d, vol_prev_14d, liq_chg_pct, stato`

All of these are reconstructed on-chain from `dex.trades`.

## `enriched_offchain_2026-06-23.csv` — off-chain-enriched

The same rows **joined with off-chain fields that the query does NOT produce**, to
show the advertised-vs-reality contrast in one table. The added columns:

| column | source | note |
|---|---|---|
| `adv_apy` | Pendle / DefiLlama | the **advertised** headline APY (max across the underlying's markets) — off-chain |
| `tvlM` | Pendle / DefiLlama | pool TVL (USD millions) — off-chain |
| `n_markets` | Pendle | number of Pendle markets on the underlying — off-chain |
| `net_if_held%` | derived | honest static proxy `(1+adv_apy)·(1+depeg)−1`, only for flagged rows; **one year of yield on top of the realized de-peg as a one-time hit** — not an annualized real APY, and it ignores the exit-liquidity risk |

So this file is **not** pure query output. The advertised APY is deliberately
off-chain (it is the number being checked, not produced). Treat `net_if_held%` as
illustrative: for a token like `apyUSD` it looks only mildly negative, yet the real
danger there is the collapsed exit liquidity — read it alongside `liq_chg_pct`, not
on its own.
