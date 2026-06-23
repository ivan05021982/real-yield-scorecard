"""Fetch daily USD price history for the lead-time study, from DefiLlama.

Reads a token config (a JSON list of `{"id": "<chain>:0x...", "symbol": "..."}`)
and writes a tidy prices CSV with columns [asset, date, price], which
run_lead_time_study.py consumes.

Source: DefiLlama coins API, `GET https://coins.llama.fi/chart/{ids}` where {ids}
is a comma-separated list of coin ids. Free, no key. See https://defillama.com/docs/api.

Usage:
    python fetch_defillama_price_history.py \
        --config ../validation/lead_time_tokens.json \
        --out    ../validation/price_history_<date>.csv \
        --span   400

Requires network access and a working TLS stack (`pip install requests`).
"""
import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

BASE = "https://coins.llama.fi/chart/"


def fetch_batch(ids, span, period):
    url = BASE + ",".join(ids)
    r = requests.get(url, params={"span": span, "period": period}, timeout=60)
    r.raise_for_status()
    return r.json().get("coins", {})


def main():
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config", default=str(here.parent / "validation" / "lead_time_tokens.json"))
    ap.add_argument("--out", default=str(here.parent / "validation" / "price_history.csv"))
    ap.add_argument("--span", type=int, default=400, help="number of daily points")
    ap.add_argument("--period", default="1d")
    ap.add_argument("--batch", type=int, default=20)
    ap.add_argument("--sleep", type=float, default=1.0, help="seconds between batches")
    args = ap.parse_args()

    ids = [c["id"] for c in json.load(open(args.config))]
    rows = []
    got = set()                 # ids that actually returned price data
    n_batches = failed_batches = 0
    for i in range(0, len(ids), args.batch):
        chunk = ids[i:i + args.batch]
        n_batches += 1
        try:
            coins = fetch_batch(chunk, args.span, args.period)
        except requests.RequestException as e:
            failed_batches += 1
            print(f"  batch {n_batches} FAILED: {e}", file=sys.stderr)
            time.sleep(args.sleep * 3)
            continue
        for cid in chunk:
            data = coins.get(cid)
            if not data or not data.get("prices"):
                continue
            got.add(cid)
            for p in data["prices"]:
                d = datetime.fromtimestamp(p["timestamp"], tz=timezone.utc).date()
                rows.append((cid, d.isoformat(), p["price"]))
        print(f"  scanned {min(i + args.batch, len(ids))}/{len(ids)} ids "
              f"({len(got)} with data so far)")
        time.sleep(args.sleep)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write("asset,date,price\n")
        for cid, d, price in rows:
            f.write(f"{cid},{d},{price}\n")
    print(f"wrote {len(rows)} rows for {len(got)}/{len(ids)} tokens -> {out}")
    print("fetched_at_utc:", datetime.now(timezone.utc).isoformat(timespec="seconds"))

    # Fail closed: a partial or empty fetch must not look like success, or the
    # downstream study would silently run on missing data.
    if failed_batches:
        sys.exit(f"ERROR: {failed_batches}/{n_batches} batches failed (network/TLS?) "
                 f"- price history is incomplete; not safe to use. Exit 1.")
    if not rows:
        sys.exit("ERROR: 0 price rows fetched — check connectivity and the config. Exit 1.")
    if len(got) < len(ids):
        print(f"WARNING: {len(ids) - len(got)} tokens returned no price data "
              f"(kept out of the output).", file=sys.stderr)


if __name__ == "__main__":
    main()
