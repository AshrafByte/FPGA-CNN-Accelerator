"""Kernel-size sweep of the three MAC architectures and of the auto-selecting system.

Builds every experiment (experiments/conv_single_chain, conv_row_chain, conv_tree) with the
experiments/flow copy of the fpga/ flow - synthesis, place and route, SAIF power, all outputs
under experiments/flow/build/ - at one kernel, no ReLU, a 32 x 32
frame and a 6.25 ns (160 MHz) clock, for kernel sizes N = 2..17, one Vivado run at a time.

Builds that cannot fit the xc7z020 are not run, with the reason recorded:
  - single chain: all N^2 slices form one PCOUT->PCIN chain, which must sit in one DSP
    column (60 slices), so N >= 8 cannot be placed;
  - row chains:   N^2 DSPs; the cascades cannot move multipliers into fabric, so N >= 15
    (225 DSPs) exceeds the device's 220;
  - tree:         the only architecture that can spill multipliers into LUTs, so N >= 15 is
    built with synth_design -max_dsp 200 (the rest of the multipliers in fabric).
If a build that was run fails (no fit, placement or routing error), larger kernel sizes of
that architecture are not continued.

The system (hw/, MAC_ARCH = 0) elaborates exactly the module its selection rule names
(K = 1: N <= 3 single chain, 4..8 row chains, 9+ tree), so its rows are the rows of that
experiment and it needs no builds of its own.

A build whose experiments/flow/build/reports/<tag>/results.csv already exists is reused, not rebuilt.

Output: experiments/sweep/results.csv (one row per design and kernel size)

usage (from the repository root):
  python experiments/sweep/run_sweep.py [--nmin 2] [--nmax 17] [--only conv_tree ...]
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FLOW = REPO / "experiments" / "flow"           # the fpga/ flow copy; fpga/ itself is not touched
BUILD = FLOW / "build"
OUT = REPO / "experiments" / "sweep" / "results.csv"
VIVADO = Path(os.environ.get("XILINX_VIVADO", r"D:\Vivado\2018.2")) / "bin" / "vivado.bat"

PERIOD = "6.250"
W = 32
DSP_TOTAL, DSP_COLUMN, SPILL_MAX_DSP = 220, 60, 200
ARCHS = [("conv_single_chain", 3), ("conv_row_chain", 2), ("conv_tree", 1)]
FIELDS = ["design", "mac_sel", "n", "status", "lut", "lutram", "ff", "dsp", "bram", "resource_points",
          "wns_ns", "fmax_mhz", "power_mw", "dynamic_mw", "static_mw", "fom", "max_dsp", "tag", "note"]


def auto_sel(n: int) -> int:
    """conv_system's MAC selection for one kernel."""
    return 3 if n <= 3 else 2 if n <= 8 else 1


def precheck(arch: str, n: int) -> str | None:
    if arch == "conv_single_chain" and n * n > DSP_COLUMN:
        return (f"not run: the single chain is one {n * n}-slice PCOUT->PCIN cascade, longer than "
                f"a {DSP_COLUMN}-slice DSP column of the xc7z020")
    if arch == "conv_row_chain" and n * n > DSP_TOTAL:
        return (f"not run: {n * n} DSPs exceed the {DSP_TOTAL} of the device, and the row chains "
                "cannot move multipliers into fabric")
    return None


def read_report(path: Path) -> dict:
    with open(path, newline="") as f:
        rows = [r for r in csv.DictReader(f) if r["benchmark"] == "random"]
    if not rows:
        raise ValueError(f"no random benchmark row in {path}")
    return rows[0]


def build(arch: str, n: int, max_dsp: int | None) -> tuple[dict | None, str]:
    tag = f"sweep_{arch}_n{n:02d}"
    report = BUILD / "reports" / tag / "results.csv"
    if report.exists():
        return read_report(report), "reused"
    args = ["RTL", arch, "N", str(n), "W", str(W), "K", "1", "RELU", "0", "PERIOD", PERIOD,
            "BENCH", "random", "TAG", tag, "STEPS", "synth+impl+power"]
    if max_dsp is not None:
        args += ["MAX_DSP", str(max_dsp)]
    logs = BUILD / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    log = logs / f"{tag}.log"
    t0 = time.time()
    r = subprocess.run([str(VIVADO), "-mode", "batch", "-notrace", "-nojournal", "-log", str(log),
                        "-source", str(FLOW / "scripts" / "run_all.tcl"), "-tclargs", *args],
                       cwd=logs, capture_output=True, text=True)
    minutes = (time.time() - t0) / 60
    if r.returncode == 0 and report.exists():
        return read_report(report), f"built in {minutes:.1f} min"
    text = log.read_text(errors="replace") if log.exists() else r.stdout
    errors = re.findall(r"^(?:ERROR|CRITICAL WARNING): (.*)$", text, re.M)
    reason = errors[0] if errors else f"Vivado exit code {r.returncode}"
    return None, f"failed after {minutes:.1f} min: {reason[:300]}"


def write(rows: list[dict]) -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, "") for k in FIELDS})


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--nmin", type=int, default=2)
    ap.add_argument("--nmax", type=int, default=17)
    ap.add_argument("--only", nargs="*", default=[a for a, _ in ARCHS])
    opts = ap.parse_args()

    rows: list[dict] = []
    for arch, sel in ARCHS:
        if arch not in opts.only:
            continue
        stopped = None
        for n in range(opts.nmin, opts.nmax + 1):
            base = {"design": arch, "mac_sel": sel, "n": n, "tag": f"sweep_{arch}_n{n:02d}"}
            reason = precheck(arch, n)
            if stopped:
                rows.append({**base, "status": "not_continued", "note": f"not continued: {stopped}"})
            elif reason:
                rows.append({**base, "status": "not_run", "note": reason})
                stopped = f"N = {n} cannot fit"
            else:
                max_dsp = SPILL_MAX_DSP if n * n > DSP_TOTAL else None
                print(f"### SWEEP {arch} N={n} max_dsp={max_dsp} ...", flush=True)
                res, note = build(arch, n, max_dsp)
                if res is None:
                    rows.append({**base, "status": "failed", "note": note})
                    stopped = f"N = {n} failed"
                else:
                    rows.append({**base, "status": "ok", "note": note, "max_dsp": max_dsp if max_dsp else "",
                                 "lut": res["lut"], "lutram": res["lutram"], "ff": res["ff"], "dsp": res["dsp"],
                                 "bram": res["bram"], "resource_points": res["resource_points"],
                                 "wns_ns": res["wns_ns"], "fmax_mhz": res["fmax_mhz"], "power_mw": res["power_mw"],
                                 "dynamic_mw": res["dynamic_mw"], "static_mw": res["static_mw"], "fom": res["fom"]})
                print(f"### SWEEP {arch} N={n}: {rows[-1]['status']} {note}", flush=True)
            write(rows)

    # The system is the experiment its selection rule elaborates at each N.
    for n in range(opts.nmin, opts.nmax + 1):
        pick = next((r for r in rows if r["n"] == n and r["mac_sel"] == auto_sel(n)), None)
        if pick:
            rows.append({**pick, "design": "system", "note": f"= {pick['design']} (MAC_ARCH 0 selects MAC_SEL {auto_sel(n)})"})
    write(rows)
    print(f"### SWEEP done: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
