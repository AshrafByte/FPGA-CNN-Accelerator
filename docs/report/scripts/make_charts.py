"""Comparison charts for the report (all numbers from ip/vivado/RESULTS.md and fpga/reports/default)."""
import re
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(sys.argv[1])
OUT = REPO / "docs" / "report" / "figures" / "charts"
OUT.mkdir(parents=True, exist_ok=True)

NAVY, BLUE, RED, GREEN, GREY, ORANGE = "#1F3A5F", "#6C8EBF", "#B85450", "#2F855A", "#999999", "#D79B00"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9, "axes.spines.top": False,
                     "axes.spines.right": False, "axes.titleweight": "bold", "axes.titlesize": 10})


def save(fig, name):
    fig.tight_layout()
    fig.savefig(OUT / name, dpi=220)
    plt.close(fig)
    print("wrote", name)


# 1. Design-space exploration (same natural-image SAIF, 250 MHz, K=1) -------------
rows = [
    ("Baseline\nmult + adder tree", 693, 0.01061, GREY),
    ("+ clock-enable\ngating", 692, 0.01063, GREY),
    ("Double MAC\n(5 DSP)", 679, 0.01023, RED),
    ("Multi-pump 3x\n(3 DSP)", 412, 0.00503, RED),
    ("DSP post-adder\nrow chains", 599, 0.01284, BLUE),
    ("+ round/sat\nsplit", 590, 0.01314, BLUE),
    ("+ bit-growth\ntree", 587, 0.01321, BLUE),
    ("Single 9-DSP\nchain", 518, 0.01520, NAVY),
]
fig, ax = plt.subplots(figsize=(7.2, 3.0))
x = range(len(rows))
bars = ax.bar(x, [r[2] for r in rows], color=[r[3] for r in rows], width=0.65)
for b, r in zip(bars, rows):
    ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 0.0002, f"{r[2]:.5f}\n({r[1]})", ha="center", va="bottom", fontsize=7)
ax.set_xticks(list(x), [r[0] for r in rows], fontsize=7)
ax.set_ylabel("FoM (natural-image SAIF)")
ax.set_ylim(0, 0.0185)
ax.set_title("Design-space exploration: FoM per approach (resource points in brackets)")
save(fig, "exploration_fom.png")

# 2. Three MAC architectures at the competition point --------------------------------
arch = ["Tree", "Row chains", "Single cascade\n(final)"]
lut = [205, 110, 70]
ff = [429, 322, 474]
fom_bars = [0.01226, 0.01483, 0.01597]
fom_check = [0.01227, 0.01612, 0.01731]
fig, (a1, a2) = plt.subplots(1, 2, figsize=(7.2, 2.8))
xs = range(3)
a1.bar([i - 0.18 for i in xs], lut, width=0.36, color=NAVY, label="LUT")
a1.bar([i + 0.18 for i in xs], ff, width=0.36, color=BLUE, label="FF (not in FoM)")
for i in xs:
    a1.text(i - 0.18, lut[i] + 6, str(lut[i]), ha="center", fontsize=7)
    a1.text(i + 0.18, ff[i] + 6, str(ff[i]), ha="center", fontsize=7)
a1.set_xticks(list(xs), arch, fontsize=7)
a1.set_title("Fabric resources (all 9 DSP, 0 BRAM)")
a1.legend(frameon=False, fontsize=7)
a2.bar([i - 0.18 for i in xs], fom_bars, width=0.36, color=ORANGE, label="Bars + Sobel-X")
a2.bar([i + 0.18 for i in xs], fom_check, width=0.36, color=GREEN, label="Checker + Sobel-Y")
for i in xs:
    a2.text(i - 0.18, fom_bars[i] + 0.0002, f"{fom_bars[i]:.4f}", ha="center", fontsize=6.5)
    a2.text(i + 0.18, fom_check[i] + 0.0002, f"{fom_check[i]:.4f}", ha="center", fontsize=6.5)
a2.set_xticks(list(xs), arch, fontsize=7)
a2.set_ylim(0, 0.0195)
a2.set_title("Figure of merit, 250 MHz")
a2.legend(frameon=False, fontsize=7, loc="upper left")
save(fig, "architectures_3x3.png")

# 3. Scaling with kernel size (K=1, 250 MHz) -------------------------------------------
N = [3, 5, 7, 9, 11, 13]
ff_chain = [479, 2742, 9971, 26775, 59325, None]
ff_rows = [335, 803, 1398, 2256, 3299, 4482]
ff_tree = [442, 993, 1799, 2913, 4271, 5953]
wns_chain = [0.63, 0.11, 0.20, -1.38, -1.56, None]
wns_rows = [0.49, 0.28, 0.20, 0.15, -0.04, -0.28]
wns_tree = [0.63, 0.51, 0.37, 0.26, 0.30, 0.14]
fig, (a1, a2) = plt.subplots(1, 2, figsize=(7.2, 2.8))
for ffs, c, lab in ((ff_chain, NAVY, "single chain"), (ff_rows, BLUE, "row chains"), (ff_tree, RED, "tree")):
    pts = [(n, v) for n, v in zip(N, ffs) if v]
    a1.plot([p[0] for p in pts], [p[1] for p in pts], marker="o", color=c, label=lab)
a1.annotate("13x13 does not fit\n(115k FF)", (11, 59325), xytext=(10.4, 14000), fontsize=7, arrowprops=dict(arrowstyle="->", lw=0.6))
a1.set_yscale("log")
a1.set_xlabel("kernel size N")
a1.set_ylabel("flip-flops")
a1.set_title("Skew flip-flops (N⁴ vs N³)")
a1.legend(frameon=False, fontsize=7)
for w, c, lab in ((wns_chain, NAVY, "single chain"), (wns_rows, BLUE, "row chains"), (wns_tree, RED, "tree")):
    pts = [(n, v) for n, v in zip(N, w) if v is not None]
    a2.plot([p[0] for p in pts], [p[1] for p in pts], marker="o", color=c, label=lab)
a2.axhline(0, color=GREY, lw=0.8, ls="--")
a2.axvspan(2.6, 3.4, color=NAVY, alpha=0.06)
a2.axvspan(3.6, 8.4, color=BLUE, alpha=0.06)
a2.axvspan(8.6, 13.4, color=RED, alpha=0.06)
a2.text(3, -1.9, "chain", ha="center", fontsize=7, color=NAVY)
a2.text(6, -1.9, "row chains", ha="center", fontsize=7, color=BLUE)
a2.text(11, -1.9, "tree", ha="center", fontsize=7, color=RED)
a2.set_ylim(-2.1, 1.0)
a2.set_xlabel("kernel size N")
a2.set_ylabel("WNS at 4.000 ns (ns)")
a2.set_title("Slack and selection bands")
save(fig, "scaling_kernel_size.png")

# 4. Operating frequency (row-chain build, SAIF at each period) -----------------------------
f = [150, 200, 250]
fom_f = [0.01424, 0.01356, 0.01284]
epp = [0.79, 0.63, 0.52]
fig, a1 = plt.subplots(figsize=(3.6, 2.6))
a1.plot(f, fom_f, marker="o", color=NAVY)
a1.set_xlabel("clock frequency (MHz)")
a1.set_ylabel("FoM", color=NAVY)
a2 = a1.twinx()
a2.plot(f, epp, marker="s", color=ORANGE)
a2.set_ylabel("energy per output pixel (nJ)", color=ORANGE)
a2.spines["right"].set_visible(True)
a1.set_title("FoM vs energy per pixel")
save(fig, "frequency_tradeoff.png")

# 5. Power breakdown of the final build on both benchmarks ---------------------------------------
def breakdown(path):
    t = path.read_text(errors="ignore")
    out = {}
    for key in ("Clocks", "Slice Logic", "Signals", "DSPs", "I/O"):
        m = re.search(r"\|\s*" + re.escape(key) + r"\s*\|\s*([0-9.]+)", t)
        out[key] = float(m.group(1)) / 1000 if m else 0.0
    m = re.search(r"Device Static \(uW\)\s*\|\s*([0-9.]+)", t)
    out["Device static"] = float(m.group(1)) / 1000
    return out

rep = REPO / "fpga" / "reports" / "default"
b1 = breakdown(rep / "power_bars_sobel_x.txt")
b2 = breakdown(rep / "power_checker_sobel_y.txt")
keys = ["Device static", "I/O", "Clocks", "Signals", "Slice Logic", "DSPs"]
colors = [GREY, ORANGE, NAVY, BLUE, GREEN, RED]
fig, ax = plt.subplots(figsize=(7.2, 1.9))
for row, (label, b) in enumerate((("Checker + Sobel-Y", b2), ("Bars + Sobel-X", b1))):
    left = 0
    for k, c in zip(keys, colors):
        ax.barh(row, b[k], left=left, color=c, label=k if row == 0 else None, height=0.55)
        if b[k] > 2.5:
            ax.text(left + b[k] / 2, row, f"{b[k]:.1f}", ha="center", va="center", fontsize=7, color="white")
        left += b[k]
    ax.text(left + 1, row, f"{left:.1f} mW", va="center", fontsize=8)
ax.set_yticks([0, 1], ["Checker + Sobel-Y", "Bars + Sobel-X"])
ax.set_xlabel("on-chip power (mW), routed, SAIF annotated")
ax.set_xlim(0, 135)
ax.legend(ncol=6, frameon=False, fontsize=7, loc="upper center", bbox_to_anchor=(0.5, 1.35))
save(fig, "power_breakdown.png")
print({k: round(v, 3) for k, v in b1.items()}, {k: round(v, 3) for k, v in b2.items()})
