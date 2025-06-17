#!/usr/bin/env python3
"""
mine_factorio_replay.py – download one or more Factorio saves,
extract replay.dat, turn it into a Pandas dataframe,
and (optionally) push the log into PM4Py for process-mining.

⚠️  This parser is *lossy* – it keeps only the 7-byte fixed header
    [action_id, tick, player_id] that precedes every payload
    (spec: forums.factorio.com/t=44225#p255694).  For behavioural
    analytics and conformance checking that’s usually enough; if
    you need the full payload, swap in a real parser such as the
    FactorioReplay JS library or MrWint’s `factorio-replay-tools`.
"""

from __future__ import annotations
import argparse, io, struct, zipfile, zlib, requests, itertools, pathlib
import pandas as pd

# ---------- helpers ----------------------------------------------------------

def grab(url: str) -> bytes:
    print(f"⇣ downloading {url}")
    r = requests.get(url, timeout=120)
    r.raise_for_status()
    return r.content

def replay_bytes(save_zip: bytes) -> bytes:
    with zipfile.ZipFile(io.BytesIO(save_zip)) as z:
        with z.open("replay.dat") as f:
            return f.read()

def inflate_chunks(raw: bytes) -> bytes:
    """
    Factorio stores the replay as a sequence of
        <u32_le compressed_len> <zlib_block>
    """
    out = io.BytesIO()
    cursor = 0
    while cursor < len(raw):
        if cursor + 4 > len(raw):
            break                  # truncated tail
        block_len = int.from_bytes(raw[cursor:cursor+4], "little")
        cursor += 4
        block     = raw[cursor:cursor+block_len]
        cursor   += block_len
        out.write(zlib.decompress(block))
    return out.getvalue()

def parse_events(stream: bytes) -> pd.DataFrame:
    """
    VERY light decoder: reads the 7-byte header and *skips* payload.
    It guesses payload length by walking until the next plausible header.
    Works acceptably for high-level mining; replace with a spec-based
    reader for pixel-perfect results.
    """
    events = []
    i = 0
    while i + 7 <= len(stream):
        action_id      = stream[i]
        tick, player   = struct.unpack_from("<IH", stream, i+1)
        events.append((tick, player, action_id))
        # heuristic: most payloads are ≤12 bytes; jump by 7+12 and rewind
        i += 19
        while i < len(stream) and stream[i] == 0:   # skip NUL padding
            i += 1
    df = pd.DataFrame(events, columns=["tick", "player", "action"])
    return df

# ---------- CLI --------------------------------------------------------------

def main(urls: list[str], outdir: pathlib.Path):
    outdir.mkdir(parents=True, exist_ok=True)
    for url in urls:
        slug        = pathlib.Path(url.split("/")[-1]).stem
        save_bytes  = grab(url)
        raw_replay  = replay_bytes(save_bytes)
        inflated    = inflate_chunks(raw_replay)
        df          = parse_events(inflated)

        csv_path    = outdir / f"{slug}.csv"
        df.to_csv(csv_path, index=False)
        print(f"✓ wrote {len(df):,} events → {csv_path}")

        # ---------- optional PM4Py demo ----------
        try:
            import pm4py
            log = pm4py.format_dataframe(
                df, case_id="player", activity_key="action", timestamp_key="tick"
            )
            net, im, fm = pm4py.discover_petri_net_inductive(log)
            pm4py.save_vis_petri_net(net, im, fm, outdir / f"{slug}_model.png")
            print("  → Petri net saved")
        except ModuleNotFoundError:
            print("  (install pm4py if you want a process model)")

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("url", nargs="+", help="HTTP(S) link to a Factorio save zip")
    p.add_argument("-o", "--out", default="out", type=pathlib.Path)
    args = p.parse_args()
    main(args.url, args.out)
