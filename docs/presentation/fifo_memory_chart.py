"""Chart for the backup slide "FIFO memory: LUTRAM or block RAM".

Evaluates the output-FIFO memory selection rule of hw/system/conv_system/src/rtl/conv_system.sv
(localparams FIFO_LUTRAM_LUTS, FIFO_BRAM_PTS, FIFO_AUTO_BRAM) for a 3x3 kernel, one kernel,
16-bit features, and plots the two costs against the image width. The values are the rule's
own estimates in figure-of-merit points, not measured builds.

    cd docs/presentation
    python fifo_memory_chart.py        # writes fifo_memory_cost.png
"""
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

IEEE = "#006699"
CRIMSON = "#B90B2E"
INK = "#1A1A1A"
MUTED = "#55595E"


def clog2(x):
    k = 0
    while (1 << k) < x:
        k += 1
    return k


def costs(w, n=3, k=1, feature_bits=16, bram_cost=100, bram_mw=4):
    """(LUTRAM points, BRAM points, BRAM chosen) exactly as conv_system computes them."""
    depth = (w - n) * (n - 1)
    ram = 1 << clog2(depth + 1)
    bits = ram * feature_bits
    lutram = ((3 * feature_bits) // 2 if ram <= 64
              else (feature_bits * ram) // 64 + (3 * feature_bits * ram) // 512) + 13 + ram // 10
    taps = n * n * k
    resource, power = 70 * taps + 100, 105 + (3 * taps) // 2
    bram = 2 * clog2(ram) + (bram_cost // 2 if bits <= 18000 else bram_cost) \
        + (resource * bram_mw + power - 1) // power
    return lutram, bram, bits <= 36000 and lutram > bram


widths = list(range(8, 301))
lutram = [costs(w)[0] for w in widths]
bram = [costs(w)[1] for w in widths]
switch = next(w for w in widths if costs(w)[2])

plt.rcParams.update({"font.family": "Segoe UI", "font.size": 17, "axes.edgecolor": MUTED,
                     "axes.labelcolor": INK, "xtick.color": INK, "ytick.color": INK})
fig, ax = plt.subplots(figsize=(10.5, 5.6), dpi=200)

ax.axvspan(8, switch, color=IEEE, alpha=0.07, lw=0)
ax.axvspan(switch, 300, color=CRIMSON, alpha=0.07, lw=0)
ax.step(widths, lutram, where="post", color=IEEE, lw=3, label="LUTRAM cost")
ax.step(widths, bram, where="post", color=CRIMSON, lw=3, ls=(0, (5, 2)), label="Block RAM cost")
ax.axvline(switch, color=MUTED, lw=1.2, ls=":")

ax.set_xscale("log", base=2)
ax.set_xticks([8, 16, 32, 64, 128, 256])
ax.set_xticklabels(["8", "16", "32", "64", "128", "256"])
ax.set_xlim(8, 300)
ax.set_ylim(0, 270)
ax.set_xlabel("Image width W (pixels), 3×3 kernel")
ax.set_ylabel("Cost in the Figure of Merit (points)")
ax.grid(axis="y", color="#D3DCE4", lw=0.8)
ax.set_axisbelow(True)
for side in ("top", "right"):
    ax.spines[side].set_visible(False)

# direct labels, in ink; the coloured line beside each carries the identity
ax.text(140, 142, "LUTRAM cost", color=INK, fontsize=17, fontweight="bold", ha="left")
ax.text(140, 66, "Block RAM cost", color=INK, fontsize=17, fontweight="bold", ha="left")
ax.text(23, 245, "LUTRAM is cheaper", color=IEEE, fontsize=17, fontweight="bold", ha="center")
ax.text(150, 245, "Block RAM is cheaper", color=CRIMSON, fontsize=17, fontweight="bold", ha="center")
ax.text(switch * 1.04, 12, "switch at W = %d" % switch, color=MUTED, fontsize=15, ha="left")

our = costs(32)
ax.plot([32, 32], [our[0], our[1]], "o", color=INK, ms=8, zorder=5)
ax.annotate("our build, 32×32:\nLUTRAM %d, block RAM %d" % (our[0], our[1]), xy=(32, our[0]),
            xytext=(9, 150), fontsize=15, color=INK, ha="left",
            arrowprops=dict(arrowstyle="-", color=MUTED, lw=1, relpos=(0.5, 0.0)))
ax.legend(loc="lower left", frameon=False, fontsize=15, ncol=2, bbox_to_anchor=(0.0, 0.0),
          handlelength=2.6, columnspacing=1.5)

fig.tight_layout()
out = Path(__file__).resolve().parent / "fifo_memory_cost.png"
fig.savefig(out, facecolor="white")
print("wrote", out, "| switch at W =", switch, "| 32x32:", our)
