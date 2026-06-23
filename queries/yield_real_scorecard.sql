-- =====================================================================
-- Real-Yield Scorecard — Dune-native, forkable, multi-chain (v2)
-- =====================================================================
-- Reconstructs, for each Pendle underlying on each chain, BOTH core axes from a
-- single dex.trades scan — no curated price oracle needed (Dune's prices.usd
-- does NOT cover the exotic underlyings where the traps live; their USD price is
-- recovered here from the trades' amount_usd, whose quote side is a blue-chip
-- token Dune prices well):
--
--   * REAL-YIELD / DE-PEG : daily ROBUST price (median of per-trade prices) vs a
--                            causal NAV reference (running max for yield-bearing,
--                            $1 for stables) — how far the underlying sits BELOW
--                            where it should be, the gap an advertised APY hides.
--   * EXIT-LIQUIDITY      : traded USD volume, last 14d vs the prior 14d, to
--                            show the "exit door that closes" (liquidity that
--                            evaporates exactly as the de-peg deepens).
--
-- Chains: Ethereum + Arbitrum + Base + BNB (the chains Dune's dex.trades indexes
-- among Pendle's deployments; Hyperliquid/Plasma/Monad are not on Dune). The
-- token universe is keyed by (symbol, blockchain) so the same asset is scored
-- independently per chain (e.g. apxUSD lives on eth, base and bnb).
--
-- ROBUSTNESS (raw dex VWAP is too noisy to ship — one bad print poisons price,
-- vol and the NAV): trade-level guards ($100..$5M), per-day MEDIAN price with a
-- >=5-trade floor, a robust daily-vol gate (median |log-return|, not stddev, so a
-- real-but-broken peg is not mistaken for a never-pegged volatile token), and a
-- liquidity floor before any BROKEN/WATCH is asserted.
--
-- The advertised APY is intentionally NOT computed here — it is the number being
-- debunked, and belongs to the off-chain aggregator (DefiLlama/Pendle).
-- Fork: edit the `tokens` VALUES list (symbol, blockchain, address).
-- =====================================================================
WITH tokens (symbol, blockchain, addr) AS (
    VALUES
    ('apxUSD', 'ethereum', 0x98a878b1cd98131b271883b390f68d2c90674665),
    ('apyUSD', 'ethereum', 0x38eeb52f0771140d10c4e9a9a72349a329fe8a6a),
    ('asdCRV', 'ethereum', 0x43e54c2e7b3e294de3a155785f52ab49d87b9922),
    ('cUSD', 'ethereum', 0xcccc62962d17b8914c62d74ffb843d73b2a3cccc),
    ('eEARN', 'ethereum', 0x9be9294722f8aad37b11a9792be2c782182cafa2),
    ('fxSAVE', 'ethereum', 0x7743e50f534a7f9f1791dde7dcd89f7783eefc39),
    ('jrNUSD', 'ethereum', 0xfc807058a352b61aeef6a38e2d0fc3990225e772),
    ('jrUSDat', 'ethereum', 0x011e55d2b28306458e37ca7e997c879bb25a455d),
    ('jrUSDe', 'ethereum', 0xc58d044404d8b14e953c115e67823784dea53d8f),
    ('loAZND', 'ethereum', 0xa6142276526724cfaee9151d280385bdf43e0503),
    ('mAPOLLO', 'ethereum', 0x7cf9dec92ca9fd46f8d86e7798b72624bc116c05),
    ('mHYPER', 'ethereum', 0x9b5528528656dbc094765e2abb79f293c21191b9),
    ('mHyperBTC', 'ethereum', 0xc8495eaff71d3a563b906295fcf2f685b1783085),
    ('msUSD', 'ethereum', 0x4ba01f22827018b4772cd326c7627fb4956a7c00),
    ('msY', 'ethereum', 0x890a5122aa1da30fec4286de7904ff808f0bd74a),
    ('nOPAL', 'ethereum', 0x119dd7daff816f29d7ee47596ae5e4bdc4299165),
    ('pufETH', 'ethereum', 0xd9a442856c234a39a81a089c06451ebaa4306a72),
    ('reUSD', 'ethereum', 0x5086bf358635b81d8c47c66d1c8b9e567db70c72),
    ('reUSDe', 'ethereum', 0xddc0f880ff6e4e22e4b74632fbb43ce4df6ccc5a),
    ('ROY-JT-apyUSD', 'ethereum', 0xab2ab53e1e2e2c5d7202918ec8c873712bcc4a2d),
    ('rswETH', 'ethereum', 0xfae103dc9cf190ed75350761e95403b7b8afa6c0),
    ('savUSD', 'ethereum', 0xb8d89678e75a973e74698c976716308abb8a46a4),
    ('sENA', 'ethereum', 0x8be3460a480c80728a8c4d7a5d5303c85ba7b3b9),
    ('SIERRA', 'ethereum', 0x6bf7788eaa948d9ffba7e9bb386e2d3c9810e0fc),
    ('siUSD', 'ethereum', 0xdbdc1ef57537e34680b898e1febd3d68c7389bcb),
    ('sNUSD', 'ethereum', 0x08efcc2f3e61185d0ea7f8830b3fec9bfa2ee313),
    ('srNUSD', 'ethereum', 0x65a44528e8868166401ea08b549e19552af589db),
    ('srUSDat', 'ethereum', 0xfaa9a0e1db9e22ae3a20b2b58a68dc24d053d066),
    ('srUSDe', 'ethereum', 0x3d7d6fdf07ee548b939a80edbc9b2256d0cdc003),
    ('stcUSD', 'ethereum', 0x88887be419578051ff9f4eb6c858a951921d8888),
    ('STRCx', 'ethereum', 0x1aad217b8f78dba5e6693460e8470f8b1a3977f3),
    ('stUSDS', 'ethereum', 0x99cd4ec3f88a45940936f469e4bb72a2a701eeb9),
    ('superUSDC', 'ethereum', 0xf6ebea08a0dfd44825f67fa9963911c81be2a947),
    ('superWETH', 'ethereum', 0xa036823b9a24f63c32553367bf181ee04229c3ac),
    ('sUSDat', 'ethereum', 0xd166337499e176bbc38a1fbd113ab144e5bd2df7),
    ('sUSDD', 'ethereum', 0xc5d6a7b61d18afa11435a889557b068bb9f29930),
    ('sUSDe', 'ethereum', 0x9d39a5de30e57443bff2a8307a4256c8797a3497),
    ('sUSDS', 'ethereum', 0xa3931d71877c0e7a3148cb7eb4463524fec27fbd),
    ('sUSN', 'ethereum', 0xe24a3dc889621612422a64e6388927901608b91d),
    ('swETH', 'ethereum', 0xf951e335afb289353dc249e82926178eac7ded78),
    ('sYUSD', 'ethereum', 0xfe0ccc9942e98c963fe6b4e5194eb6e3baa4cb64),
    ('tmvUSDC', 'ethereum', 0x697c54a84d83f37380d034e2bfc6f7ce8d89f4ee),
    ('uniETH', 'ethereum', 0xf1376bcef0f78459c0ed0ba5ddce976f1ddf51f4),
    ('USD3', 'ethereum', 0x056b269eb1f75477a8666ae8c7fe01b64dd55ecc),
    ('USDat', 'ethereum', 0x23238f20b894f29041f48d88ee91131c395aaa71),
    ('USDe', 'ethereum', 0x4c9edd5852cd905f086c759e8383e09bff1e68b3),
    ('USDG', 'ethereum', 0xe343167631d89b6ffc58b88d6b7fb0228795491d),
    ('USP', 'ethereum', 0x098697ba3fee4ea76294c5d6a466a4e3b3e95fe6),
    ('weETH', 'ethereum', 0xcd5fe23c85820f7b72d0926fc9b05b43e359b7ee),
    ('weETHs', 'ethereum', 0x917cee801a67f933f2e6b33fc0cd1ed2d5909d88),
    ('WOUSD', 'ethereum', 0xd2af830e8cbdfed6cc11bab697bb25496ed6fa62),
    ('wstETH', 'ethereum', 0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0),
    ('ynRWAx', 'ethereum', 0x01ba69727e2860b37bc1a2bd56999c1afb4c15d8),
    ('GUSDC', 'arbitrum', 0xd3443ee1e91af28e5fb858fbd0d72a63ba8046e0),
    ('RETH', 'arbitrum', 0xec70dcb4a1efa46b8f2d97c310c9c4790ba5ffa8),
    ('SUSDAI', 'arbitrum', 0x0b2b2b2076d95dda7817e785989fe353fe955ef9),
    ('UNIETH', 'arbitrum', 0x3d15fd46ce9e551498328b1c83071d9509e2c3a0),
    ('USDAI', 'arbitrum', 0x0a1a1a107e45b7ced86833863f482bc5f4ed82ef),
    ('WEETH', 'arbitrum', 0x35751007a407ca6feffe80b3cb397736d2cf4dbe),
    ('WSTETH', 'arbitrum', 0x5979d7b546e38e414f7e9822514be443a4800529),
    ('40ACRESUSDC', 'base', 0xcd7079e32bf53093f60bf973c28e5d72937c12f2),
    ('APXUSD', 'base', 0xd993935e13851dd7517af10687ec7e5022127228),
    ('SKAITO', 'base', 0x548d3b444da39686d1a6f1544781d154e7cd1ef7),
    ('WSUPEROETHB', 'base', 0x7fcd174e80f264448ebee8c88a7c4476aaf58ea6),
    ('YOUSD', 'base', 0x0000000f2eb9f69274678c76222b35eec7588a65),
    ('APXUSD', 'bnb', 0x6b3788fd6604bbf03c5378d24e57bb334baad4af),
    ('CUSDO', 'bnb', 0x64748ea3e31d0b7916f0ff91b017b9f404ded8ef),
    ('SLISBNBX', 'bnb', 0xb0b84d294e0c75a6abe60171b70edeb2efd14a1b),
    ('SUSDAT', 'bnb', 0x9cd57d3685e6868cacaa8bdcaaf52cbdebf4fa25),
    ('USDAT', 'bnb', 0x0bb150dfa86ea5d7742f07fefcd8e8eda81d64ef)
),
-- one row per (token, trade): which side is the underlying, its per-trade
-- implied USD price, the trade's USD value. Trade-level guards drop dust and
-- fat-finger prints BEFORE aggregation. Pushdown filters (chain + address IN)
-- prune dex.trades; the JOIN attributes symbol/chain precisely.
trades AS (
    SELECT
        date_trunc('day', t.block_time) AS d,
        tk.symbol,
        tk.blockchain,
        t.amount_usd,
        t.amount_usd / (CASE WHEN t.token_bought_address = tk.addr
                             THEN t.token_bought_amount ELSE t.token_sold_amount END) AS p
    FROM dex.trades t
    JOIN tokens tk
      ON t.blockchain = tk.blockchain
     AND (t.token_bought_address = tk.addr OR t.token_sold_address = tk.addr)
    WHERE t.block_time > now() - interval '180' day
      AND t.amount_usd BETWEEN 100 AND 5e6
      AND t.blockchain IN (SELECT DISTINCT blockchain FROM tokens)
      AND ( t.token_bought_address IN (SELECT addr FROM tokens)
         OR t.token_sold_address  IN (SELECT addr FROM tokens) )
),
trades_ok AS (
    SELECT * FROM trades WHERE p > 0
),
-- daily ROBUST price = median of per-trade prices + volume. A day is trusted for
-- pricing only with >= 5 trades; thin days are dropped (honest: a barely-traded
-- token cannot be priced from its trades).
daily AS (
    SELECT symbol, blockchain, d,
           sum(amount_usd)           AS vol_usd,
           approx_percentile(p, 0.5) AS price,
           count(*)                  AS n_tr
    FROM trades_ok
    GROUP BY symbol, blockchain, d
    HAVING count(*) >= 5
),
rets AS (
    SELECT symbol, blockchain, d, price, vol_usd,
           ln(price) - lag(ln(price)) OVER (PARTITION BY symbol, blockchain ORDER BY d) AS lr
    FROM daily
),
-- per-token regime: median price (stable vs yield-bearing) + ROBUST daily vol
-- (median |log-return|, MAD-style — keeps calm-then-broken pegs as peg-class,
-- excludes tokens that swing every day like CRV).
meta AS (
    SELECT symbol, blockchain,
           approx_percentile(price, 0.5)      AS med_price,
           approx_percentile(abs(lr), 0.5)    AS realized_vol,
           max(d)                             AS last_d
    FROM rets
    GROUP BY symbol, blockchain
),
-- causal NAV: running max for yield-bearing, $1 for stables.
-- NOTE: the running max is taken over the query's trailing window (the 180-day
-- filter in `trades`), NOT all-time. For a monotonically-accruing token this
-- tracks the recent NAV closely; for one whose all-time high predates the window
-- the reference is the in-window high, so the de-peg is, if anything, understated.
nav AS (
    SELECT r.symbol, r.blockchain, r.d, r.price, r.vol_usd,
           m.med_price, m.realized_vol, m.last_d,
           CASE WHEN m.med_price > 1.03
                THEN max(r.price) OVER (PARTITION BY r.symbol, r.blockchain ORDER BY r.d
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                ELSE 1.0 END AS nav_ref
    FROM rets r
    JOIN meta m ON r.symbol = m.symbol AND r.blockchain = m.blockchain
),
scored AS (
    SELECT symbol, blockchain, d, price, med_price, realized_vol, last_d, nav_ref,
           (price / nullif(nav_ref, 0) - 1.0) * 100.0 AS depeg_pct,
           sum(vol_usd) OVER (PARTITION BY symbol, blockchain ORDER BY d
               RANGE BETWEEN INTERVAL '13' day PRECEDING AND CURRENT ROW)                AS vol_14d,
           sum(vol_usd) OVER (PARTITION BY symbol, blockchain ORDER BY d
               RANGE BETWEEN INTERVAL '27' day PRECEDING AND INTERVAL '14' day PRECEDING) AS vol_prev_14d
    FROM nav
)
SELECT
    s.symbol,
    s.blockchain                   AS chain,
    -- stato first (the headline read): honest gating, structural scope (non-USD
    -- reference) -> never-pegged volatile -> liquidity floor (a -X% on trivial
    -- volume is noise) -> de-peg.
    CASE
        WHEN s.med_price > 3.0 OR s.med_price < 0.3 THEN '~ non-USD-reference / out-of-scope'
        WHEN s.realized_vol > 0.012                 THEN '~ volatile (market risk)'
        WHEN s.depeg_pct < -1.5 AND s.vol_14d < 1e5 THEN '~ thin/illiquid (depeg unverified)'
        WHEN s.depeg_pct < -8.0                     THEN 'BROKEN'
        WHEN s.depeg_pct < -1.5                     THEN 'WATCH'
        ELSE 'healthy'
    END                            AS stato,
    round(s.depeg_pct, 2)          AS depeg_now_pct,
    round(s.vol_14d, 0)            AS exit_liq_14d,
    CASE WHEN s.vol_prev_14d > 0
         THEN round((s.vol_14d / s.vol_prev_14d - 1.0) * 100, 0) END AS liq_chg_pct,
    round(s.med_price, 4)          AS med_price,
    round(s.realized_vol * 100, 3) AS realized_vol_pct,
    round(s.price, 4)              AS last_price,
    round(s.nav_ref, 4)            AS nav_ref,
    round(s.vol_prev_14d, 0)       AS vol_prev_14d
FROM scored s
WHERE s.d = s.last_d                              -- latest snapshot per (token, chain)
ORDER BY (s.med_price > 3.0 OR s.med_price < 0.3), s.realized_vol > 0.012, s.depeg_pct ASC
