"""Waveforms from the Vivado xsim simulations of the FPGA flow.

Re-runs two simulations of fpga/scripts in their build directories with a VCD dump and
renders them in the style of waveform.py:
  xsim_power_frame.png   - power benchmark (bars + Sobel-X): the whole 32x32 frame
  xsim_power_rowedge.png - the same run zoomed on a row edge after the FIFO prefill
  xsim_board_frames.png  - conv_axi_lite_tb (3x3, 32x32, K = 1): six frames through AXI
  xsim_board_axi.png     - one PIXELS4 write feeding four pixels, and the end of a frame

Run the FPGA flow first (steps board_sim and power), which compiles both builds.
usage: vivado_waves.py <repo> <out_dir> [--no-sim]
"""
import os
import subprocess
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
OUT.mkdir(parents=True, exist_ok=True)
VIVADO = Path(os.environ.get("XILINX_VIVADO", r"D:\Vivado\2018.2"))
BOARD_DIR = REPO / "fpga" / "sim" / "build" / "board" / "n3_w32_k1_r0"
POWER_DIR = REPO / "fpga" / "sim" / "build" / "default" / "bars_sobel_x"


def tool(name):
    return str(VIVADO / "bin" / (name + ".bat" if os.name == "nt" else name))


def run(cmd, cwd, log):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    (cwd / log).write_text(r.stdout + r.stderr)
    if r.returncode != 0 or "ERROR:" in r.stdout:
        print(r.stdout[-3000:], r.stderr[-2000:])
        raise SystemExit(f"failed: {' '.join(cmd)} (log {cwd / log})")
    return r.stdout


def vcd_tcl(cwd, name, objects):
    lines = [f"open_vcd {name}.vcd"]
    for o in objects:
        parts = o.split("/")
        gen = next((i for i, p in enumerate(parts) if "[" in p), None)
        if gen is None:
            lines.append(f'if {{[catch {{log_vcd [get_objects {{{o}}}]}} e]}} {{puts "WAVE missing {o}"}}')
            continue
        # xsim names a generate block as one escaped scope, e.g. \gen_mac[0].gen_single_chain.u_mac:
        # find it among the parent's scopes and log the signal from inside it
        parent = "/".join(parts[:gen])
        glob = "*" + ".".join(parts[gen:-1]).replace("[", "?").replace("]", "?") + "*"
        lines.append(
            f'foreach s [get_scopes {{{parent}/*}}] {{ if {{[string match {{{glob}}} $s]}} {{ '
            f'if {{[catch {{current_scope $s; log_vcd [get_objects {parts[-1]}]}} e]}} {{puts "WAVE missing {o}: $e"}}; '
            f'current_scope {{{parent}}} }} }}')
    lines += ["run -all", "close_vcd", "quit"]
    (cwd / f"{name}.tcl").write_text("\n".join(lines) + "\n")


# ---- signals: label -> (hierarchical path, signed, hex) ---------------------------------
P = "/conv_system_power_tb"
D = f"{P}/u_dut"
POWER = {
    "clk": (f"{P}/clk", False, False),
    "rst_n": (f"{P}/rst_n", False, False),
    "i_weight_valid": (f"{P}/i_weight_valid", False, False),
    "i_pixel_valid": (f"{P}/i_pixel_valid", False, False),
    "i_data": (f"{P}/i_data", False, False),
    "rows_ready": (f"{D}/w_rows_ready", False, False),
    "window_valid": (f"{D}/w_window_valid", False, False),
    "mac o_valid": (f"{D}/gen_mac[0]/gen_single_chain/u_mac/o_valid", False, False),
    "mac o_sum": (f"{D}/gen_mac[0]/gen_single_chain/u_mac/o_sum", True, False),
    "round_sat o_valid": (f"{D}/gen_round_sat[0]/u_round_saturate/o_valid", False, False),
    "round_sat o_data": (f"{D}/gen_round_sat[0]/u_round_saturate/o_data", True, False),
    "q_prefilled": (f"{D}/gen_output_fifo[0]/u_output_fifo/q_prefilled", False, False),
    "o_valid": (f"{P}/o_valid", False, False),
    "o_frame_done": (f"{P}/o_frame_done", False, False),
    "o_feature[0]": (f"{D}/gen_output_fifo[0]/u_output_fifo/o_data", True, False),
}
B = "/conv_axi_lite_tb"
W = f"{B}/u_dut"
BOARD = {
    "clk": (f"{B}/clk", False, False),
    "AXI awvalid": (f"{B}/awvalid", False, False),
    "AXI awready": (f"{B}/awready", False, False),
    "AXI awaddr": (f"{B}/awaddr", False, True),
    "AXI wdata": (f"{B}/wdata", False, True),
    "AXI arvalid": (f"{B}/arvalid", False, False),
    "AXI araddr": (f"{B}/araddr", False, True),
    "AXI rvalid": (f"{B}/rvalid", False, False),
    "AXI rdata": (f"{B}/rdata", False, True),
    "core rst_n": (f"{W}/r_core_rst_n", False, False),
    "core weight_valid": (f"{W}/r_core_weight_valid", False, False),
    "core pixel_valid": (f"{W}/r_core_pixel_valid", False, False),
    "core i_data": (f"{W}/r_core_data", False, True),
    "core o_valid": (f"{W}/w_core_valid", False, False),
    "core o_frame_done": (f"{W}/w_core_frame_done", False, False),
    "STATUS[2] done": (f"{W}/r_done", False, False),
    "PIXEL_COUNT": (f"{W}/r_pixel_count", False, False),
    "OUT_COUNT": (f"{W}/r_out_count", False, False),
    "FRAME_COUNT": (f"{W}/r_frame_count", False, False),
    "leds": (f"{B}/leds", False, True),
}

if "--no-sim" not in sys.argv:
    vcd_tcl(POWER_DIR, "wave_power", [p for p, _, _ in POWER.values()])
    out = run([tool("xsim"), "power_snap", "-tclbatch", "wave_power.tcl"], POWER_DIR, "wave_power.txt")
    print([l for l in out.splitlines() if "[POWER]" in l or "WAVE" in l])
    run([tool("xelab"), "-debug", "typical", "-timescale", "1ns/1ps", "-s", "wave_snap",
         "xil_defaultlib.conv_axi_lite_tb"], BOARD_DIR, "wave_xelab.txt")
    vcd_tcl(BOARD_DIR, "wave_board", [p for p, _, _ in BOARD.values()])
    out = run([tool("xsim"), "wave_snap", "-tclbatch", "wave_board.tcl"], BOARD_DIR, "wave_board.txt")
    print([l for l in out.splitlines() if "[BOARD]" in l or "TEST" in l or "WAVE" in l])
    if "TEST PASSED" not in out:
        raise SystemExit("board testbench did not pass")


# ---- VCD ---------------------------------------------------------------------------------
class Wave:
    def __init__(self, path, signals):
        codes, widths, trace = {}, {}, {}
        scope, t = [], 0
        with open(path) as f:
            for line in f:
                tok = line.split()
                if not tok:
                    continue
                h = tok[0]
                if h == "$scope":
                    scope.append(tok[2].lstrip("\\"))
                elif h == "$upscope":
                    scope.pop()
                elif h == "$var":
                    codes.setdefault("/" + "/".join(scope + [tok[4].lstrip("\\")]), tok[3])
                    widths[tok[3]] = int(tok[2])
                elif h[0] == "#":
                    t = int(h[1:])
                elif h[0] in "bB" and len(tok) == 2:
                    trace.setdefault(tok[1], []).append((t, h[1:]))
                elif h[0] in "01xzXZ":
                    trace.setdefault(h[1:], []).append((t, h[0]))
        self.w = {}
        for label, (path_, signed, hexa) in signals.items():
            want = path_.replace(" ", "").split("/", 2)[-1]
            # generate scopes appear as gen_mac[0].gen_single_chain.u_mac: compare with '.' as '/'
            hits = [p for p in codes if p.replace(" ", "").replace(".", "/").endswith(want)]
            if not hits:
                print(f"  not in VCD: {label} ({path_})")
                continue
            code = codes[min(hits, key=len)]
            self.w[label] = (trace.get(code, []), widths[code], signed, hexa)
        self.rises = [tt for tt, b in self.w["clk"][0] if b == "1"]
        self.period = self.rises[1] - self.rises[0]
        self.t0 = self.rises[0]

    def cyc(self, tt):
        return (tt - self.t0) / self.period

    def value(self, label, bits):
        _, width, signed, _ = self.w[label]
        if bits is None or any(c in "xXzZ" for c in bits):
            return None
        v = int(bits.rjust(width, "0"), 2)
        if signed and v >> (width - 1):
            v -= 1 << width
        return v

    def at_edges(self, label):
        """Value just before each rising clock edge."""
        changes = self.w[label][0]
        out, i, cur = [], 0, None
        for r in self.rises:
            while i < len(changes) and changes[i][0] < r:
                cur = changes[i][1]
                i += 1
            out.append(self.value(label, cur))
        return out


def draw(ax, wv, labels, start, stop, title, marks=()):
    labels = [l for l in labels if l in wv.w]
    span = stop - start
    min_text = max(0.9, span / 45)
    for row, label in enumerate(labels):
        y = len(labels) - 1 - row
        changes, width, signed, hexa = wv.w[label]
        colour = "#B85450" if ("done" in label) else \
                 "#2F855A" if ("valid" in label or "ready" in label or "rst" in label) else "#1F3A5F"
        if label == "clk":
            xs, ys = [], []
            k = int(start)
            while k <= stop:
                xs += [k, k, k + 0.5, k + 0.5]
                ys += [y + 0.1, y + 0.8, y + 0.8, y + 0.1]
                k += 1
            ax.plot(xs, ys, color="#1F3A5F", lw=0.8)
        else:
            segs = [(wv.cyc(tt), b) for tt, b in changes] + [(stop + 1, None)]
            if width == 1:
                xs, ys = [], []
                for (c, b), (c2, _) in zip(segs[:-1], segs[1:]):
                    a, e = max(c, start), min(c2, stop)
                    if e <= a:
                        continue
                    lvl = y + (0.8 if b == "1" else 0.1)
                    if xs and xs[-1] == a:
                        xs.append(a)
                        ys.append(lvl)
                    xs += [a, e]
                    ys += [lvl, lvl]
                ax.plot(xs, ys, color=colour, lw=1.2 if colour == "#B85450" else 1.0)
            else:
                for (c, b), (c2, _) in zip(segs[:-1], segs[1:]):
                    a, e = max(c, start), min(c2, stop)
                    if e <= a:
                        continue
                    v = wv.value(label, b)
                    d = min(0.12 * span / 40, (e - a) / 2)
                    ax.fill([a, a + d, e - d, e, e - d, a + d],
                            [y + 0.45, y + 0.8, y + 0.8, y + 0.45, y + 0.1, y + 0.1],
                            facecolor="#F1F5FA" if v not in (None, 0) else "white", edgecolor="#6C8EBF", lw=0.6)
                    if v is not None and e - a >= min_text:
                        ax.text((a + e) / 2, y + 0.45, f"{v:X}" if hexa else str(v),
                                ha="center", va="center", fontsize=6.2)
        ax.text(start - span * 0.008, y + 0.45, label, ha="right", va="center", fontsize=7.5, family="monospace")
    marks = sorted(marks)
    for k, (x, text) in enumerate(marks):
        ax.axvline(x, color="#B85450", lw=0.6, ls=":")
        # neighbouring marks closer than 6 % of the span: push the labels apart
        near_next = k + 1 < len(marks) and marks[k + 1][0] - x < 0.06 * span
        near_prev = k > 0 and x - marks[k - 1][0] < 0.06 * span
        ha = "right" if near_next else "left" if near_prev else "center"
        if x > start + 0.93 * span:
            ha = "right"            # keep labels at the plot edges inside the axes
        elif x < start + 0.04 * span:
            ha = "left"
        ax.text(x, len(labels) + 0.05, text, ha=ha, va="bottom", fontsize=7, color="#B85450")
    ax.set_xlim(start, stop)
    ax.set_ylim(-0.3, len(labels) + (0.7 if marks else 0))
    ax.set_yticks([])
    ax.set_xlabel("clock cycle")
    for s in ("left", "right", "top"):
        ax.spines[s].set_visible(False)
    ax.grid(axis="x", color="#E3E8EF", lw=0.5)
    ax.set_title(title, fontsize=9, loc="left", fontweight="bold", pad=16 if marks else 6)


def save(fig, name, left=0.14):
    fig.subplots_adjust(left=left, right=0.99, top=0.9, bottom=0.1, hspace=0.55)
    fig.savefig(OUT / name, dpi=220)
    plt.close(fig)
    print("wrote", OUT / name)


def hits(values, want=1):
    return [i for i, v in enumerate(values) if v == want]


# ---- power benchmark ---------------------------------------------------------------------
pw = Wave(POWER_DIR / "wave_power.vcd", POWER)
pix = hits(pw.at_edges("i_pixel_valid"))
ov = pw.at_edges("o_valid")
ov_i = hits(ov)
done = hits(pw.at_edges("o_frame_done"))
wv_ = pw.at_edges("window_valid")
run_len, best = 0, 0
for v in ov:
    run_len = run_len + 1 if v == 1 else 0
    best = max(best, run_len)
print(f"power: pixels {len(pix)} (edges {pix[0]}..{pix[-1]}), window_valid {sum(1 for v in wv_ if v == 1)}, "
      f"o_valid {len(ov_i)} (first {ov_i[0]}, longest run {best}), o_frame_done at {done}")
c = pw.cyc
fig, ax = plt.subplots(figsize=(12, 4.6))
draw(ax, pw, ["rst_n", "i_weight_valid", "i_pixel_valid", "i_data", "rows_ready", "window_valid", "mac o_valid",
              "q_prefilled", "o_valid", "o_frame_done", "o_feature[0]"],
     0, c(pw.rises[done[0]]) + 25,
     "xsim power benchmark (bars + Sobel-X, 250 MHz): one 32 x 32 frame after the kernel load",
     marks=[(c(pw.rises[pix[0]]), "first pixel"), (c(pw.rises[ov_i[0]]), "first feature"),
            (c(pw.rises[pix[-1]]), "last pixel"), (c(pw.rises[done[0]]), "o_frame_done")])
save(fig, "xsim_power_frame.png")

gap = next(i for i in range(ov_i[0] + 40, len(ov)) if wv_[i] != 1 and ov[i] == 1)
fig, ax = plt.subplots(figsize=(12, 4.8))
draw(ax, pw, ["clk", "i_pixel_valid", "i_data", "window_valid", "mac o_valid", "mac o_sum", "round_sat o_valid",
              "round_sat o_data", "q_prefilled", "o_valid", "o_feature[0]"],
     c(pw.rises[gap]) - 12, c(pw.rises[gap]) + 16,
     "xsim power benchmark, zoom on a row edge: window_valid drops for N - 1 = 2 pixels, o_valid stays high",
     marks=[(c(pw.rises[gap]), "row edge")])
save(fig, "xsim_power_rowedge.png")

# ---- board wrapper -----------------------------------------------------------------------
bw = Wave(BOARD_DIR / "wave_board.vcd", BOARD)
bdone = hits(bw.at_edges("core o_frame_done"))
rst = bw.at_edges("core rst_n")
resets = [i for i in range(1, len(rst)) if rst[i] == 0 and rst[i - 1] == 1]
print(f"board: {len(bw.rises)} cycles, o_frame_done at {bdone}, soft resets at {resets}")
b = bw.cyc
marks = [(b(bw.rises[i]), f"frame {k + 1}") for k, i in enumerate(bdone)] + \
        [(b(bw.rises[i]), "soft reset") for i in resets]
fig, ax = plt.subplots(figsize=(13, 4.6))
draw(ax, bw, ["core rst_n", "AXI awvalid", "AXI arvalid", "core weight_valid", "core pixel_valid", "core o_valid",
              "core o_frame_done", "STATUS[2] done", "FRAME_COUNT", "leds"],
     0, len(bw.rises) - 1,
     "xsim conv_axi_lite_tb: soft reset, then five frames without a reset, a second soft reset and a sixth frame",
     marks=marks)
save(fig, "xsim_board_frames.png")

aw = bw.at_edges("AXI awvalid")
addr = bw.at_edges("AXI awaddr")
first4 = next(i for i in range(bdone[0], len(aw)) if aw[i] == 1 and addr[i] == 0x20)
fig, (a1, a2) = plt.subplots(2, 1, figsize=(12, 8.2))
draw(a1, bw, ["clk", "AXI awvalid", "AXI awready", "AXI awaddr", "AXI wdata", "core pixel_valid", "core i_data",
              "PIXEL_COUNT", "STATUS[2] done"],
     b(bw.rises[first4]) - 3, b(bw.rises[first4]) + 17,
     "(a) frame 2 starts: a PIXELS4 write (0x020) feeds four pixels, one per cycle, and clears the done flag")
d2 = bdone[1]
draw(a2, bw, ["clk", "core o_valid", "core o_frame_done", "OUT_COUNT", "STATUS[2] done", "AXI arvalid",
              "AXI araddr", "AXI rvalid", "AXI rdata", "leds"],
     b(bw.rises[d2]) - 8, b(bw.rises[d2]) + 22,
     "(b) frame 2 ends: o_frame_done sets STATUS[2] and LED LD2; the next STATUS poll reads 0x5",
     marks=[(b(bw.rises[d2]), "o_frame_done")])
save(fig, "xsim_board_axi.png")
