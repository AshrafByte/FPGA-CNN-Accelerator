"""A HarnessRun turned into terminal output, CSV files and a PNG grid."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

from ..core.reference import drop_bits
from ..core.rendering import normalise, save_grid
from ..harness import HarnessRun
from . import terminal


def report(run: HarnessRun, args: argparse.Namespace) -> bool:
    """Print a run - per kernel its card, stats, verdict and preview - then PNG, CSV, footer.

    Everything is computed by the harness; this only formats it. Returns whether
    every kernel matched.
    """
    comparison, result = run.comparison, run.result
    size = comparison.image.shape[0]
    window = comparison.lanes[0].kernel.size
    drop = drop_bits(window)
    shown = comparison.rectified() if args.relu else comparison
    shown_input = normalise(comparison.image)

    for lane in shown.lanes:
        print()
        print(terminal.rule(f"kernel {lane.index}: {lane.kernel.name}"))
        print(terminal.kernel_card(lane.kernel, drop))
        print()

        if lane.hardware is not None:
            print(f"  hardware   {terminal.stats(lane.hardware)}")
        print(f"  reference  {terminal.stats(lane.reference)}")
        if lane.verdict is not None:
            print(f"  {lane.verdict.summary()}")
        if args.relu:
            print(f"  relu       {terminal.stats(lane.frames()['reference'])}")

        if args.csv:
            for name, frame in lane.frames().items():
                path = _csv_path(args.csv, lane.kernel.name, name)
                np.savetxt(path, frame, fmt="%d", delimiter=",")
                print(f"  csv        {path}")

        print()
        print(terminal.side_by_side({"input": shown_input, **lane.display_frames()}))

    if args.png:
        print(f"\nwrote {save_grid(shown.grid_rows(), args.png)}")

    print()
    print(terminal.rule())
    count = len(comparison.lanes)
    if result is None:
        print(f"reference model only (--reference, no simulator): signed MAC -> "
              f"round-half-up >>{drop} -> saturate. Nothing was checked against the RTL.")
    else:
        print(f"Questa elaborated conv_system at INPUT_SIZE={size}, WINDOW_SIZE={window}, "
              f"NUM_KERNELS={count} in {result.elapsed_s:.1f}s   "
              f"(artifacts: {result.run_dir})")
        if comparison.mismatched:
            names = ", ".join(lane.kernel.name for lane in comparison.mismatched)
            print(f"MISMATCH in {len(comparison.mismatched)} of {count} kernel(s): {names}")
        else:
            print(f"MATCH: hardware and reference agree bit for bit on all {count} kernel(s)")
    if args.relu:
        print("ReLU was applied to what is displayed and saved; the verdict is on raw features.")
    return comparison.all_match


def _csv_path(base: Path, kernel_name: str, source: str) -> Path:
    return base.with_name(f"{base.stem}_{kernel_name}_{source}{base.suffix or '.csv'}")
