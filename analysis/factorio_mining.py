#!/usr/bin/env python3
"""
factorio_mining.py

A more robust PM4Py pipeline for mining Factorio task traces.
- Segments a long Lua‐based trace into cases (by launch events or fixed windows).
- Sorts and cleans the log.
- Filters out low‐frequency variants.
- Discovers a Petri net via Inductive Miner (with noise threshold).
- Performs conformance checking (alignments).
- Exports visualizations.
"""

import argparse
import logging
import re
from pathlib import Path

import pandas as pd
import pm4py
from pm4py.objects.conversion.log import converter as log_converter
from pm4py.objects.log.util import sorting as log_sorting
from pm4py.algo.filtering.log.variants import variants_filter
from pm4py.algo.discovery.inductive import algorithm as inductive_miner
from pm4py.algo.conformance.alignments import algorithm as alignments
from pm4py.visualization.petrinet import visualizer as pn_visualizer


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def parse_lua_to_df(lua_path: Path) -> pd.DataFrame:
    """Parse a Factorio tasks.lua file into a DataFrame of events."""
    events = []
    for line in lua_path.read_text().splitlines():
        line = line.strip()
        if not line.startswith("task[") or "}" not in line:
            continue

        # extract index and parameters
        idx = int(re.match(r"task\[(\d+)\]", line).group(1))
        content = re.search(r"{(.+)}", line).group(1)

        # very simple split, tweak if you have nested braces
        parts = [p.strip() for p in re.split(r",(?=(?:[^\"']|\"[^\"]*\"|'[^']*')*$)", content)]
        activity = parts[0].strip('"')

        # synthetic timestamp based on idx; replace with real timestamps if available
        ts = pd.Timestamp("2024-01-01") + pd.Timedelta(seconds=idx)

        row = {
            "case:concept:name": None,           # to be filled in segmentation
            "concept:name": activity,
            "time:timestamp": ts,
            "task_id": idx,
        }
        # extract coordinates if present
        if activity in ("walk", "move", "build", "mine", "put", "take") and len(parts) > 1:
            coords = re.findall(r"-?\d+\.?\d*", parts[1])
            if len(coords) >= 2:
                row["x"] = float(coords[0])
                row["y"] = float(coords[1])
        events.append(row)

    df = pd.DataFrame(events)
    logger.info(f"Parsed {len(df)} raw events with {df['concept:name'].nunique()} activities")
    return df


def segment_cases(df: pd.DataFrame, split_activity: str = None, window_size: int = None) -> pd.DataFrame:
    """
    Assign 'case:concept:name' based on:
    - split_activity: each time this activity appears, increment case ID, OR
    - window_size: fixed-size windows of events per case.
    """
    if split_activity:
        case_id = 0
        df["case:concept:name"] = ""
        for i, act in enumerate(df["concept:name"]):
            if act == split_activity:
                case_id += 1
            df.at[i, "case:concept:name"] = f"session_{case_id}"
    elif window_size:
        df = df.reset_index(drop=True)
        df["case:concept:name"] = df.index // window_size
        df["case:concept:name"] = df["case:concept:name"].apply(lambda x: f"win_{x}")
    else:
        df["case:concept:name"] = "full_run"
    n_cases = df["case:concept:name"].nunique()
    logger.info(f"Segmented into {n_cases} case(s)")
    return df


def preprocess_log(df: pd.DataFrame, 
                   sort: bool = True, 
                   variant_min_freq: int = 2) -> "EventLog":
    """
    - Optionally sort by timestamp
    - Filter out variants occurring fewer than variant_min_freq times
    - Convert to PM4Py EventLog
    """
    if sort:
        df = log_sorting.sort_values(df, timestamp_key="time:timestamp")
    # filter rare variants
    if variant_min_freq > 1:
        df = variants_filter.filter_variants_by_count(df, 
                                                      variant_count=variant_min_freq, 
                                                      parameters={"variant_key": "concept:name"})
        logger.info(f"After filtering, {df['case:concept:name'].nunique()} cases remain")
    log = pm4py.format_dataframe(df, case_id="case:concept:name", 
                                 activity_key="concept:name", timestamp_key="time:timestamp")
    return log_converter.apply(log)


def discover_and_export(log, noise_threshold: float, output_dir: Path):
    """Run Inductive Miner and export Petri net visuals."""
    params = {"noise_threshold": noise_threshold}
    tree = inductive_miner.apply_tree(log, parameters=params)
    net, im, fm = inductive_miner.apply(log, parameters=params)
    gviz = pn_visualizer.apply(net, im, fm)
    output_dir.mkdir(parents=True, exist_ok=True)
    pn_visualizer.save(gviz, str(output_dir / "petri_net.png"))
    logger.info(f"Petri net saved to {output_dir/'petri_net.png'}")
    return net, im, fm


def conformance_check(log, net, im, fm, output_dir: Path):
    """Run alignments and export a summary CSV."""
    aligned = alignments.apply_log(log, net, im, fm)
    df_fit = pm4py.convert_to_dataframe(aligned)
    output_dir.mkdir(parents=True, exist_ok=True)
    df_fit.to_csv(output_dir / "conformance.csv", index=False)
    avg_fit = df_fit["fitness"].mean()
    logger.info(f"Average fitness: {avg_fit:.3f}; details in {output_dir/'conformance.csv'}")


def main():
    p = argparse.ArgumentParser(description="Factorio Process Mining with PM4Py")
    p.add_argument("lua_file", type=Path, help="path to tasks.lua")
    p.add_argument("--split-activity", default="launch",
                   help="activity name to split cases on (mutually exclusive with --window-size)")
    p.add_argument("--window-size", type=int, help="fixed # events per case")
    p.add_argument("--variant-min-freq", type=int, default=2,
                   help="drop variants occurring fewer times")
    p.add_argument("--noise-threshold", type=float, default=0.2,
                   help="Inductive Miner noise threshold")
    p.add_argument("--outdir", type=Path, default=Path("results"),
                   help="directory to save outputs")
    args = p.parse_args()

    df = parse_lua_to_df(args.lua_file)
    df = segment_cases(df, split_activity=args.split_activity, window_size=args.window_size)
    log = preprocess_log(df, sort=True, variant_min_freq=args.variant_min_freq)

    net, im, fm = discover_and_export(log, noise_threshold=args.noise_threshold, output_dir=args.outdir)
    conformance_check(log, net, im, fm, output_dir=args.outdir)


if __name__ == "__main__":
    main()