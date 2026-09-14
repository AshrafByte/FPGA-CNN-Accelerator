"""Simulate conv_image_tb in QuestaSim with a VCD dump and render the waveforms.

8x8 frame (ramp with a vertical edge), Sobel-X, competition datapath (3x3, single
chain). A small frame keeps the whole frame readable: reset, kernel load, line
buffer fill, window valid, MAC, round/saturate, output FIFO prefill and drain.

usage: waveform.py <repo> <out_dir>
"""
import subprocess
import sys
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(sys.argv[1])
OUT = Path(sys.argv[2])
RUN = REPO / "sw" / ".run_wave"
RUN.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

sys.path.insert(0, str(REPO / "sw"))
from conv_lab.core.kernels import preset               # noqa: E402
from conv_lab.hardware.contract import write_stimulus  # noqa: E402

SIZE = int(sys.argv[sys.argv.index("--size") + 1]) if "--size" in sys.argv else 8
EVENTS_ONLY = "--events-only" in sys.argv
RUN = RUN.with_name(f".run_wave_{SIZE}")
RUN.mkdir(parents=True, exist_ok=True)
image = np.tile((np.arange(SIZE) * 10 + 20).astype(np.uint8), (SIZE, 1))
image[:, SIZE // 2:] = 200                             # vertical edge for Sobel-X
write_stimulus(RUN / "stimulus.txt", image, [preset("sobel_x")])

T = "/conv_image_tb/u_dut"
SIGNALS = [  # label, path, signed
    ("clk", f"{T}/clk", False),
    ("rst_n", f"{T}/rst_n", False),
    ("i_weight_valid", f"{T}/i_weight_valid", False),
    ("i_pixel_valid", f"{T}/i_pixel_valid", False),
    ("i_data", f"{T}/i_data", False),
    ("rows_ready", f"{T}/w_rows_ready", False),
    ("window_valid", f"{T}/w_window_valid", False),
    ("mac o_valid", f"{T}/gen_mac[0]/gen_single_chain/u_mac/o_valid", False),
    ("mac o_sum", f"{T}/gen_mac[0]/gen_single_chain/u_mac/o_sum", True),
    ("round_sat o_valid", f"{T}/gen_round_sat[0]/u_round_saturate/o_valid", False),
    ("round_sat o_data", f"{T}/gen_round_sat[0]/u_round_saturate/o_data", True),
    ("o_valid", f"{T}/o_valid", False),
    ("o_feature[0]", f"{T}/gen_output_fifo[0]/u_output_fifo/o_data", True),
]
compile_f = REPO / "hw" / "system" / "conv_system" / "sim" / "compile.f"
# Braces: the generate paths contain [0], which Tcl would execute as a command.
do = ("vcd file wave.vcd; " + "; ".join("vcd add {%s}" % p for _, p, _ in SIGNALS)
      + "; run -all; vcd flush; quit -f")


def run(cmd):
    r = subprocess.run(cmd, cwd=RUN, capture_output=True, text=True)
    if r.returncode != 0 or "** Error" in r.stdout:
        print(r.stdout[-3000:], r.stderr[-2000:])
        raise SystemExit(f"failed: {cmd[0]}")
    return r.stdout


if "--no-sim" not in sys.argv:
    run(["vlib", "work"])
    run(["vlog", "-sv", "-timescale", "1ns/1ps", "-F", str(compile_f)])
    run(["vsim", "-c", "-voptargs=+acc", f"-gINPUT_SIZE={SIZE}", "work.conv_image_tb", "+stim=stimulus.txt",
         "+result=features.txt", "-do", do])

# ---- VCD ---------------------------------------------------------------------------------
names, widths, trace = {}, {}, {}
scope, t = [], 0
for line in open(RUN / "wave.vcd"):
    tok = line.split()
    if not tok:
        continue
    if tok[0] == "$scope":
        scope.append(tok[2])
    elif tok[0] == "$upscope":
        scope.pop()
    elif tok[0] == "$var":
        names.setdefault(tok[3], []).append("/".join(scope + [tok[4]]))
        widths[tok[3]] = int(tok[2])
    elif tok[0].startswith("#"):
        t = int(tok[0][1:])
    elif tok[0][0] in "bB" and len(tok) == 2:
        trace.setdefault(tok[1], []).append((t, tok[0][1:]))
    elif tok[0][0] in "01xzXZ":
        trace.setdefault(tok[0][1:], []).append((t, tok[0][0]))


def lookup(path):
    parts = [p.split("[")[0] for p in path.strip("/").split("/")]
    leaf = parts[-1]
    best = None
    for code, ns in names.items():
        for n in ns:
            np_ = [p.split("[")[0].split("(")[0] for p in n.split("/")]
            if np_[-1] == leaf and all(p in np_ for p in parts[-3:-1]):
                best = code
    if best is None:
        raise KeyError(path)
    return best


def value(bits, width, signed):
    if any(c in "xXzZ" for c in bits):
        return None
    v = int(bits, 2)
    if signed and v >> (width - 1):
        v -= 1 << width
    return v


waves = {}
for label, path, signed in SIGNALS:
    code = lookup(path)
    waves[label] = (trace.get(code, []), widths[code], signed)

clk_changes = waves["clk"][0]
rises = [tt for tt, b in clk_changes if b == "1"]
period = rises[1] - rises[0]
t0 = rises[0]


def cyc(tt):
    return (tt - t0) / period


def first(label, level="1"):
    for tt, b in waves[label][0]:
        if b == level:
            return cyc(tt)
    return None


events = {k: first(k) for k in ("i_weight_valid", "i_pixel_valid", "window_valid", "mac o_valid",
                                 "round_sat o_valid", "o_valid")}
print("first-high cycles:", {k: round(v, 1) for k, v in events.items() if v is not None})


def count_high(label):
    """Cycles in which a 1-bit signal is high at the rising clock edge."""
    changes = waves[label][0]
    n, prev_run = 0, None
    highs = []
    for r in rises:
        lvl = "0"
        for tt, b in changes:
            if tt < r:
                lvl = b
            else:
                break
        highs.append(lvl == "1")
    return highs


ov = count_high("o_valid")
first_o = ov.index(True)
last_o = len(ov) - 1 - ov[::-1].index(True)
burst = sum(ov[first_o:last_o + 1])
pv = count_high("i_pixel_valid")
first_p = pv.index(True)
wv = count_high("window_valid")
mv = count_high("mac o_valid")
rv = count_high("round_sat o_valid")
print(f"SIZE={SIZE}: first pixel at edge {first_p}, first window {wv.index(True)}, first mac {mv.index(True)}, "
      f"first round_sat {rv.index(True)}, first o_valid {first_o}, last o_valid {last_o}")
print(f"latency first pixel -> first feature: {first_o - first_p} cycles; "
      f"window->mac {mv.index(True) - wv.index(True)}, mac->round_sat {rv.index(True) - mv.index(True)}")
print(f"features {burst} over {last_o - first_o + 1} cycles (gaps {last_o - first_o + 1 - burst}); "
      f"frame {SIZE*SIZE} pixels, first pixel -> last feature {last_o - first_p} cycles")
if EVENTS_ONLY:
    raise SystemExit(0)


def draw(ax, start, stop, title):
    labels = [s[0] for s in SIGNALS]
    for row, label in enumerate(labels):
        y = len(labels) - 1 - row
        changes, width, signed = waves[label]
        # value at each segment
        segs = []
        cur = None
        for tt, b in changes:
            c = cyc(tt)
            segs.append((c, b))
        segs.append((stop + 1, None))
        if label == "clk":
            xs, ys = [], []
            k = int(np.floor(start))
            while k <= stop:
                xs += [k, k, k + 0.5, k + 0.5]
                ys += [y + 0.1, y + 0.8, y + 0.8, y + 0.1]
                k += 1
            ax.plot(xs, ys, color="#1F3A5F", lw=0.8)
        elif width == 1:
            xs, ys = [], []
            for (c, b), (c2, _) in zip(segs[:-1], segs[1:]):
                a, e = max(c, start), min(c2, stop)
                if e <= a:
                    continue
                lvl = y + (0.8 if b == "1" else 0.1)
                xs += [a, e]
                ys += [lvl, lvl]
            ax.plot(xs, ys, color="#2F855A" if "valid" in label or label == "rows_ready" else "#1F3A5F",
                    lw=1.1, drawstyle="default")
            # vertical edges
            for (c, b), (c2, b2) in zip(segs[:-2], segs[1:-1]):
                if start <= c2 <= stop and b != b2:
                    ax.plot([c2, c2], [y + 0.1, y + 0.8], color="#2F855A" if "valid" in label or label == "rows_ready" else "#1F3A5F", lw=1.1)
        else:
            for (c, b), (c2, _) in zip(segs[:-1], segs[1:]):
                a, e = max(c, start), min(c2, stop)
                if e <= a:
                    continue
                v = value(b, width, signed)
                d = min(0.12, (e - a) / 2)
                ax.fill([a, a + d, e - d, e, e - d, a + d], [y + 0.45, y + 0.8, y + 0.8, y + 0.45, y + 0.1, y + 0.1],
                        facecolor="#F1F5FA" if v not in (None, 0) else "white", edgecolor="#6C8EBF", lw=0.7)
                if v is not None and e - a >= 0.9:
                    ax.text((a + e) / 2, y + 0.45, str(v), ha="center", va="center", fontsize=6.3)
        ax.text(start - 0.6, y + 0.45, label, ha="right", va="center", fontsize=7.5, family="monospace")
    ax.set_xlim(start - 0.2, stop)
    ax.set_ylim(-0.3, len(labels))
    ax.set_yticks([])
    ax.set_xlabel("clock cycle")
    for s in ("left", "right", "top"):
        ax.spines[s].set_visible(False)
    ax.grid(axis="x", color="#E3E8EF", lw=0.5)
    ax.set_title(title, fontsize=9, loc="left", fontweight="bold")


a0 = events["i_weight_valid"] - 2
a1 = events["round_sat o_valid"] + 6
fig, ax = plt.subplots(figsize=(12, 4.6))
draw(ax, a0, a1, "(a) kernel load, line-buffer fill, first valid window, 11-cycle DSP cascade and rounding")
fig.subplots_adjust(left=0.13, right=0.99, top=0.93, bottom=0.12)
fig.savefig(OUT / "wave_start.png", dpi=220)
plt.close(fig)

b = events["o_valid"]
fig, ax = plt.subplots(figsize=(11, 4.6))
draw(ax, b - 22, b + 20, "(b) output FIFO prefill, then one feature per clock cycle until the frame drains")
fig.subplots_adjust(left=0.13, right=0.99, top=0.93, bottom=0.12)
fig.savefig(OUT / "wave_output.png", dpi=220)
plt.close(fig)
print("wrote wave_start.png, wave_output.png")
