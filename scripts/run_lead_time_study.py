"""Lead-time study for the de-peg signal — reproducible, self-contained.

Question: when a severe de-peg happens, does it arrive gradually (so a causal
read would have warned, with lead time) or as a step (no warning)?

Method (causal, no look-ahead), per underlying:
  - de-spike the price (rolling-median filter);
  - expected value = 1 for stablecoins, causal running max for yield-bearing
    (a NAV proxy using past values only);
  - depeg(t) = price/expected - 1;
  - a SEVERE event = an asset whose causal depeg troughs below -5%;
  - lead time = days from the first time depeg crossed -2% (the warning) to the
    trough.

It measures whether the signal precedes the damage. It does NOT predict which
healthy asset will break, and the trough is located retrospectively (so the
lead time measures the duration of the slide, not the timing of the minimum).

Two scope notes, stated openly:
  - the de-spike filter (which removes data glitches) can also mask a de-peg that
    happens in a SINGLE day, so genuinely sudden breaks are under-represented in
    this event set. The study therefore characterises GRADUAL de-pegs — exactly
    the population for which a lead time is meaningful;
  - never-pegged volatile underlyings are excluded (same gate as the scorecard),
    so a falling governance token is not miscounted as a de-peg event.

Usage:
    python run_lead_time_study.py \
        --prices   ../validation/price_history_<date>.csv \
        --config   ../validation/lead_time_tokens.json \
        --out      ../validation/lead_time_events_<date>.csv

The prices CSV is produced by fetch_defillama_price_history.py and has columns
[asset, date, price] where `asset` is a DefiLlama coin id ("chain:0x...").
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

WARN_PCT = -2.0       # warning threshold (de-peg first crosses this)
SEVERE_PCT = -5.0     # an event is "severe" if the trough is below this
MIN_OBS = 40          # need at least this many daily points to assess
OFFSETS = [30, 21, 14, 7, 3, 0]


def to_float(x):
    try:
        return float(str(x).replace(",", "."))
    except (TypeError, ValueError):
        return np.nan


def despike(values):
    s = pd.Series(values, dtype=float)
    med7 = s.rolling(7, center=True, min_periods=3).median()
    denom = med7.abs().replace(0, np.nan)
    ratio = (s - med7).abs().divide(denom)
    mask = (ratio > 0.10).fillna(False)
    return s.where(~mask).ffill().bfill().values


def classify(p):
    return "yld" if (np.median(p) > 1.03 or p[-1] / p[0] - 1 > 0.03) else "stable"


def main():
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--prices", default=str(here.parent / "validation" / "price_history.csv"))
    ap.add_argument("--config", default=str(here.parent / "validation" / "lead_time_tokens.json"))
    ap.add_argument("--out", default=str(here.parent / "validation" / "lead_time_events.csv"))
    args = ap.parse_args()

    symbols = {}
    cfg_path = Path(args.config)
    if cfg_path.exists():
        symbols = {c["id"].lower(): c.get("symbol", "") for c in json.load(open(cfg_path))}

    if not Path(args.prices).exists():
        sys.exit(f"ERROR: prices file not found: {args.prices}. "
                 f"Run fetch_defillama_price_history.py first. Exit 1.")
    px = pd.read_csv(args.prices)
    required = {"asset", "date", "price"}
    missing_cols = required - set(px.columns)
    if missing_cols:
        sys.exit(f"ERROR: prices file {args.prices} is missing columns "
                 f"{sorted(missing_cols)} (need asset,date,price). Exit 1.")
    if px.empty:
        sys.exit(f"ERROR: prices file {args.prices} has no rows. Exit 1.")
    px["date"] = pd.to_datetime(px["date"], errors="coerce")
    px["price"] = px["price"].map(to_float)
    px = px.dropna(subset=["date", "price"])
    if px.empty:
        sys.exit(f"ERROR: prices file {args.prices} has no parseable date/price rows. Exit 1.")

    events, traj = [], []
    for asset in px["asset"].unique():
        s = px[px.asset == asset].sort_values("date")
        if len(s) < MIN_OBS:
            continue
        dates = s["date"].values
        price = s["price"].values
        if not (0.3 <= np.median(price) <= 3.0):       # scope: USD-reference only
            continue
        pc = despike(price)
        # Scope gate, consistent with the scorecard: exclude never-pegged volatile
        # underlyings (a falling governance/reward token like CRV is market risk,
        # not a de-peg). Robust daily vol = median |log-return|; > 1.2% => volatile.
        lr = np.diff(np.log(np.clip(pc, 1e-9, None)))
        if len(lr) and np.median(np.abs(lr)) > 0.012:
            continue
        cls = classify(pc)
        expected = np.ones(len(pc)) if cls == "stable" else np.maximum.accumulate(pc)
        depeg = (np.divide(pc, expected) - 1.0) * 100.0
        imin = int(np.argmin(depeg))
        trough = depeg[imin]
        if trough >= SEVERE_PCT or imin <= 3:          # not severe, or trough too early to assess
            continue
        warn = next((i for i in range(imin + 1) if depeg[i] < WARN_PCT), None)
        if warn is not None:
            lead = (pd.Timestamp(dates[imin]) - pd.Timestamp(dates[warn])).days
            warn_date = str(pd.Timestamp(dates[warn]).date())
        else:
            lead, warn_date = 0, ""
        events.append({
            "symbol": symbols.get(str(asset).lower(), ""),
            "coin_id": asset,
            "asset_class": cls,
            "trough_pct": round(float(trough), 1),
            "first_minus_2_date": warn_date,
            "bottom_date": str(pd.Timestamp(dates[imin]).date()),
            "lead_days": int(lead),
            "sudden_flag": bool(lead <= 1),
        })
        row = {}
        for off in OFFSETS:
            j = imin - off
            row[f"t-{off}"] = round(float(depeg[j]), 1) if j >= 0 else np.nan
        traj.append(row)

    if not events:
        sys.exit("ERROR: no severe de-peg events found. Either the prices input is "
                 "empty/too short (need >= 40 daily points per token) or no asset in "
                 "scope troughed below -5%. Check the fetch step succeeded. Exit 1.")

    ev = pd.DataFrame(events).sort_values("trough_pct")
    # De-duplicate to distinct underlyings: the same asset can appear under several
    # coin ids (multiple deployments / Pendle SY-PT-YT variants of one market). Keep
    # the deepest trough per known symbol, so the count is distinct episodes, not
    # token-series. Rows without a symbol are treated as distinct.
    ev["_grp"] = ev["symbol"].where(ev["symbol"].astype(bool), ev["coin_id"])
    ev = ev.drop_duplicates("_grp", keep="first").drop(columns="_grp")
    ev = ev.sort_values("trough_pct").reset_index(drop=True)
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    ev.to_csv(args.out, index=False)

    n = len(ev)
    print(f"severe de-peg events (trough < {SEVERE_PCT:.0f}%): {n}")
    if n:
        lead = ev["lead_days"]
        print(f"LEAD TIME (days, first {WARN_PCT:.0f}% warning -> trough): "
              f"median {int(lead.median())} | mean {round(lead.mean(), 1)} | max {int(lead.max())}")
        for thr in [7, 14]:
            k = int((lead >= thr).sum())
            print(f"  events with lead >= {thr}d: {k}/{n} ({round(100*k/n)}%)")
        print(f"  sudden (lead <= 1d): {int(ev['sudden_flag'].sum())}/{n}")
        print("MEAN depeg-% trajectory before the trough (gradualness):")
        print(pd.DataFrame(traj).mean().round(1).to_string())
    print("saved ->", args.out)


if __name__ == "__main__":
    main()
