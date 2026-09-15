"""Simulate conv_image_tb in QuestaSim with a VCD dump and render the waveforms.

Two 8x8 frames streamed back to back after one reset (a ramp with a vertical edge,
then its mirror), Sobel-X, competition datapath (3x3, single chain). A small frame
keeps every phase readable:
  (a) wave_start.png  - reset, kernel load, line buffer fill, window valid, MAC, rounding
  (b) wave_output.png - output FIFO prefill and one feature per cycle
  (c) wave_frames.png - the frame boundary: row counter wrap, frame-end mark, prefill
                        re-arm and o_frame_done, with no reset between the frames

usage: waveform.py <repo> <out_dir> [--size N] [--no-sim] [--events-only]
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
OUT.mkdir(parents=True, exist_ok=True)

sys.path.insert(0, str(REPO / "sw"))
from conv_lab.core.kernels import preset                        # noqa: E402
from conv_lab.hardware.contract import write_stream_stimulus    # noqa: E402

SIZE = int(sys.argv[sys.argv.index("--size") + 1]) if "--size" in sys.argv else 8
EVENTS_ONLY = "--events-only" in sys.argv
RUN = REPO / "sw" / f".run_wave_{SIZE}"
RUN.mkdir(parents=True, exist_ok=True)

frame1 = np.tile((np.arange(SIZE) * 10 + 20).astype(np.uint8), (SIZE, 1))
frame1[:, SIZE // 2:] = 200                             # vertical edge for Sobel-X
frame2 = frame1[:, ::-1].copy()                         # mirrored: the edge changes sign
write_stream_stimulus(RUN / "stimulus.txt", [frame1, frame2], [preset("sobel_x")])

T = "/conv_image_tb/u_dut"
FIFO = f"{T}/gen_output_fifo[0]/u_output_fifo"
ALL = {  # name: (path, signed)
    "clk": (f"{T}/clk", False),
    "rst_n": (f"{T}/rst_n", False),
    "i_weight_valid": (f"{T}/i_weight_valid", False),
    "i_pixel_valid": (f"{T}/i_pixel_valid", False),
    "i_data": (f"{T}/i_data", False),
    "last row": (f"{T}/u_line_buffer/w_last_row", False),
    "rows_ready": (f"{T}/w_rows_ready", False),
    "frame_end": (f"{T}/w_frame_end", False),
    "window_valid": (f"{T}/w_window_valid", False),
    "mac o_valid": (f"{T}/gen_mac[0]/gen_single_chain/u_mac/o_valid", False),
    "mac o_sum": (f"{T}/gen_mac[0]/gen_single_chain/u_mac/o_sum", True),
    "round_sat o_valid": (f"{T}/gen_round_sat[0]/u_round_saturate/o_valid", False),
    "round_sat o_data": (f"{T}/gen_round_sat[0]/u_round_saturate/o_data", True),
    "last mark @FIFO": (f"{T}/w_post_last", False),
    "q_prefilled": (f"{FIFO}/q_prefilled", False),
    "o_valid": (f"{T}/o_valid", False),
    "o_frame_done": (f"{T}/o_frame_done", False),
    "o_feature[0]": (f"{FIFO}/o_data", True),
}
SET_START = ["clk", "rst_n", "i_weight_valid", "i_pixel_valid", "i_data", "rows_ready", "window_valid",
             "mac o_valid", "mac o_sum", "round_sat o_valid", "round_sat o_data", "o_valid", "o_feature[0]"]
SET_OUTPUT = SET_START
SET_FRAMES = ["clk", "i_pixel_valid", "i_data", "last row", "rows_ready", "frame_end", "window_valid",
              "round_sat o_valid", "last mark @FIFO", "q_prefilled", "o_valid", "o_frame_done", "o_feature[0]"]

compile_f = REPO / "hw" / "system" / "conv_system" / "sim" / "compile.f"
# Braces: the generate paths contain [0], which Tcl would execute as a command.
do = ("vcd file wave.vcd; " + "; ".join("vcd add {%s}" % p for p, _ in ALL.values())
      + "; run -all; vcd flush; quit -f")


def run(cmd):
    r = subprocess.run(cmd, cwd=RUN, capture_output=True, text=True)
    if r.returncode != 0 or "** Error" in r.stdout or "STATUS: ERROR" in r.stdout:
        print(r.stdout[-3000:], r.stderr[-2000:])
        raise SystemExit(f"failed: {cmd[0]}")
    return r.stdout


if "--no-sim" not in sys.argv:
    run(["vlib", "work"])
    run(["vlog", "-sv", "-timescale", "1ns/1ps", "-F", str(compile_f)])
    log = run(["vsim", "-c", "-voptargs=+acc", f"-gINPUT_SIZE={SIZE}", "work.conv_image_tb", "+stim=stimulus.txt",
               "+result=features.txt", "-do", do])
    print([l for l in log.splitlines() if "conv_image_tb" in l or "conv_system]" in l])

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
            if np_[-1] == leaf and all(p in np_ for p in parts[-3:-1]) and len(np_) == len(parts):
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
for label, (path, signed) in ALL.items():
    code = lookup(path)
    waves[label] = (trace.get(code, []), widths[code], signed)

rises = [tt for tt, b in waves["clk"][0] if b == "1"]
period = rises[1] - rises[0]
t0 = rises[0]


def cyc(tt):
    return (tt - t0) / period


def high_at_edges(label):
    """Level of a 1-bit signal just before each rising clock edge."""
    changes = waves[label][0]
    out, i, lvl = [], 0, "0"
    for r in rises:
        while i < len(changes) and changes[i][0] < r:
            lvl = changes[i][1]
            i += 1
        out.append(lvl == "1")
    return out


edges = {k: high_at_edges(k) for k in ("i_weight_valid", "i_pixel_valid", "window_valid", "mac o_valid",
                                        "round_sat o_valid", "o_valid", "o_frame_done", "frame_end",
                                        "last mark @FIFO")}


def idx(label, nth=0, value=True):
    hits = [i for i, v in enumerate(edges[label]) if v == value]
    return hits[nth] if len(hits) > nth else None


per_frame = SIZE * SIZE
first_p = idx("i_pixel_valid")
ov = edges["o_valid"]
done = [i for i, v in enumerate(edges["o_frame_done"]) if v]
marks = [i for i, v in enumerate(edges["frame_end"]) if v]
lasts = [i for i, v in enumerate(edges["last mark @FIFO"]) if v]
print(f"SIZE={SIZE}: first pixel at edge {first_p}, first window {idx('window_valid')}, "
      f"first mac {idx('mac o_valid')}, first round_sat {idx('round_sat o_valid')}, first o_valid {idx('o_valid')}")
print(f"latency first pixel -> first feature: {idx('o_valid') - first_p} cycles; "
      f"window->mac {idx('mac o_valid') - idx('window_valid')}, mac->round_sat {idx('round_sat o_valid') - idx('mac o_valid')}")
print(f"frame-end marks at {marks}, marks at FIFO input {lasts}, o_frame_done at {done}, "
      f"o_valid count {sum(ov)} (expected {2 * (SIZE - 2) ** 2})")
print(f"frame 1: first pixel {first_p} -> last feature {done[0]} = {done[0] - first_p} cycles; "
      f"frame 2: first pixel {first_p + per_frame} -> first feature {idx('o_valid', (SIZE - 2) ** 2)} "
      f"-> last feature {done[1]} = {done[1] - first_p - per_frame} cycles")
if EVENTS_ONLY:
    raise SystemExit(0)


def draw(ax, labels, start, stop, title, marks_at=()):
    for row, label in enumerate(labels):
        y = len(labels) - 1 - row
        changes, width, signed = waves[label]
        segs = [(cyc(tt), b) for tt, b in changes] + [(stop + 1, None)]
        colour = "#2F855A" if ("valid" in label or label == "rows_ready") else \
                 "#B85450" if label in ("o_frame_done", "frame_end", "last mark @FIFO") else "#1F3A5F"
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
            ax.plot(xs, ys, color=colour, lw=1.3 if colour == "#B85450" else 1.1)
            for (c, b), (c2, b2) in zip(segs[:-2], segs[1:-1]):
                if start <= c2 <= stop and b != b2:
                    ax.plot([c2, c2], [y + 0.1, y + 0.8], color=colour, lw=1.3 if colour == "#B85450" else 1.1)
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
    for x, text in marks_at:
        ax.axvline(x, color="#B85450", lw=0.6, ls=":")
        ax.text(x, len(labels) + 0.05, text, ha="center", va="bottom", fontsize=7, color="#B85450")
    ax.set_xlim(start - 0.2, stop)
    ax.set_ylim(-0.3, len(labels) + (0.6 if marks_at else 0))
    ax.set_yticks([])
    ax.set_xlabel("clock cycle")
    for s in ("left", "right", "top"):
        ax.spines[s].set_visible(False)
    ax.grid(axis="x", color="#E3E8EF", lw=0.5)
    ax.set_title(title, fontsize=9, loc="left", fontweight="bold", pad=14 if marks_at else 6)


def save(fig, name):
    fig.subplots_adjust(left=0.13, right=0.99, top=0.9, bottom=0.12)
    fig.savefig(OUT / name, dpi=220)
    plt.close(fig)


a0 = 0.0                                               # from power-up, so the reset release shows
a1 = cyc(rises[idx("round_sat o_valid")]) + 6
fig, ax = plt.subplots(figsize=(12, 4.6))
draw(ax, SET_START, a0, a1, "(a) kernel load, line-buffer fill, first valid window, 11-cycle DSP cascade and rounding")
save(fig, "wave_start.png")

b = cyc(rises[idx("o_valid")])
fig, ax = plt.subplots(figsize=(11, 4.6))
draw(ax, SET_OUTPUT, b - 22, b + 20, "(b) output FIFO prefill, then one feature per clock cycle until the frame drains")
save(fig, "wave_output.png")

last_pixel_1 = first_p + per_frame - 1
c0 = cyc(rises[last_pixel_1]) - 5
c1 = cyc(rises[idx("o_valid", (SIZE - 2) ** 2)]) + 4
fig, ax = plt.subplots(figsize=(13, 4.9))
draw(ax, SET_FRAMES, c0, c1,
     "(c) frame boundary without reset: frame 2 follows frame 1 back to back",
     marks_at=[(cyc(rises[last_pixel_1 + 1]), "frame 2, first pixel"),
               (cyc(rises[done[0]]), "o_frame_done (frame 1)"),
               (cyc(rises[idx("o_valid", (SIZE - 2) ** 2)]), "frame 2, first feature")])
save(fig, "wave_frames.png")
print("wrote wave_start.png, wave_output.png, wave_frames.png")
