"""Report block diagrams as one draw.io file (one page per figure).

Page names are the PNG file names used by docs/report/main.typ.

usage (from the repo root):
  python docs/report/scripts/diagrams.py docs/resources/diagrams/report_figures.drawio
  python docs/report/scripts/export_diagrams.py docs/resources/diagrams/report_figures.drawio docs/report/figures/diagrams
"""
from __future__ import annotations

import sys
from pathlib import Path
from xml.sax.saxutils import quoteattr

OUT = Path(sys.argv[1])

FONT = "fontFamily=Helvetica;"
BASE = "whiteSpace=wrap;html=1;fontSize=16;" + FONT
ST = {
    "reg":   BASE + "rounded=0;fillColor=#fff2cc;strokeColor=#d6b656;",
    "win":   BASE + "rounded=0;fillColor=#f8cecc;strokeColor=#b85450;",
    "dsp":   BASE + "rounded=1;arcSize=10;fillColor=#dae8fc;strokeColor=#6c8ebf;",
    "mem":   BASE + "rounded=1;arcSize=10;fillColor=#e1d5e7;strokeColor=#9673a6;",
    "logic": BASE + "rounded=1;arcSize=14;fillColor=#ffffff;strokeColor=#444444;",
    "opt":   BASE + "rounded=1;arcSize=14;fillColor=#ffffff;strokeColor=#444444;dashed=1;",
    "op":    BASE + "ellipse;fillColor=#ffffff;strokeColor=#444444;fontSize=24;fontStyle=1;",
    "add":   BASE + "ellipse;fillColor=#f8cecc;strokeColor=#b85450;fontSize=24;fontStyle=1;",
    "bar":   BASE + "rounded=0;fillColor=#fff2cc;strokeColor=#d6b656;fontSize=12;",
    "dec":   BASE + "rhombus;fillColor=#ffffff;strokeColor=#444444;",
    "state": BASE + "rounded=1;arcSize=35;fillColor=#fff2cc;strokeColor=#d6b656;",
    "term":  BASE + "rounded=1;arcSize=50;fillColor=#eeeeee;strokeColor=#888888;",
    "group": ("rounded=1;arcSize=3;whiteSpace=wrap;html=1;fillColor=#fafafa;strokeColor=#a0a0a0;dashed=1;"
              "verticalAlign=top;align=left;spacingLeft=12;spacingTop=6;fontStyle=1;fontSize=17;fontColor=#1f3a5f;" + FONT),
    "frame": ("rounded=1;arcSize=3;whiteSpace=wrap;html=1;fillColor=#f7f9fc;strokeColor=#6c8ebf;strokeWidth=2;"
              "verticalAlign=top;align=left;spacingLeft=14;spacingTop=8;fontStyle=1;fontSize=18;fontColor=#1f3a5f;" + FONT),
    "board": ("rounded=1;arcSize=2;whiteSpace=wrap;html=1;fillColor=#e8f3e8;strokeColor=#2e7d32;strokeWidth=2;"
              "verticalAlign=top;align=left;spacingLeft=14;spacingTop=8;fontStyle=1;fontSize=19;fontColor=#1b5e20;" + FONT),
    "soc":   ("rounded=1;arcSize=2;whiteSpace=wrap;html=1;fillColor=#f4f4f4;strokeColor=#555555;strokeWidth=2;"
              "verticalAlign=top;align=left;spacingLeft=14;spacingTop=8;fontStyle=1;fontSize=18;fontColor=#333333;" + FONT),
    "ps":    ("rounded=1;arcSize=3;whiteSpace=wrap;html=1;fillColor=#e3edf9;strokeColor=#6c8ebf;"
              "verticalAlign=top;align=left;spacingLeft=12;spacingTop=6;fontStyle=1;fontSize=17;fontColor=#1f3a5f;" + FONT),
    "pl":    ("rounded=1;arcSize=3;whiteSpace=wrap;html=1;fillColor=#fdf6e3;strokeColor=#d6b656;"
              "verticalAlign=top;align=left;spacingLeft=12;spacingTop=6;fontStyle=1;fontSize=17;fontColor=#7a5c00;" + FONT),
    "doc":   BASE + "shape=note;size=16;fillColor=#ffffff;strokeColor=#666666;fontSize=15;",
    "pass":  BASE + "rounded=1;arcSize=30;fillColor=#e8f5e9;strokeColor=#2e7d32;fontColor=#1b5e20;fontSize=15;",
    "led":   "ellipse;whiteSpace=wrap;html=1;fillColor=#66bb6a;strokeColor=#2e7d32;",
    "laptop": "shape=mxgraph.networks.laptop;html=1;fillColor=#f5f5f5;strokeColor=#555555;",
    "io":    "text;html=1;align=center;verticalAlign=middle;fontSize=16;" + FONT,
    "ior":   "text;html=1;align=right;verticalAlign=middle;fontSize=16;" + FONT,
    "iol":   "text;html=1;align=left;verticalAlign=middle;fontSize=16;" + FONT,
    "head":  "text;html=1;align=center;verticalAlign=middle;fontSize=15;fontStyle=1;fontColor=#1f3a5f;" + FONT,
    "small": "text;html=1;align=center;verticalAlign=middle;fontSize=13;fontColor=#555555;" + FONT,
    "red":   "text;html=1;align=center;verticalAlign=middle;fontSize=15;fontStyle=1;fontColor=#c0392b;" + FONT,
}
EDGE = ("edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;html=1;endArrow=block;endFill=1;"
        "strokeWidth=1.6;fontSize=14;labelBackgroundColor=#ffffff;" + FONT)
DASH = "dashed=1;strokeColor=#777777;strokeWidth=1.3;"
CASC = "strokeColor=#c0392b;strokeWidth=3;"


class Page:
    def __init__(self, name: str):
        self.name, self.cells, self.n = name, [], 1

    def node(self, kind, x, y, w, h, label="", extra=""):
        self.n += 1
        i = f"c{self.n}"
        self.cells.append(
            f'<mxCell id="{i}" value={quoteattr(label)} style={quoteattr(ST[kind] + extra)} vertex="1" parent="1">'
            f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        return i

    def edge(self, s, t, label="", extra="", pts=(), ex=None, en=None):
        self.n += 1
        i = f"c{self.n}"
        style = EDGE + extra
        if ex:
            style += f"exitX={ex[0]};exitY={ex[1]};exitDx=0;exitDy=0;"
        if en:
            style += f"entryX={en[0]};entryY={en[1]};entryDx=0;entryDy=0;"
        points = ""
        if pts:
            points = '<Array as="points">' + "".join(f'<mxPoint x="{x}" y="{y}"/>' for x, y in pts) + "</Array>"
        self.cells.append(
            f'<mxCell id="{i}" value={quoteattr(label)} style={quoteattr(style)} edge="1" parent="1" '
            f'source="{s}" target="{t}"><mxGeometry relative="1" as="geometry">{points}</mxGeometry></mxCell>')
        return i

    def xml(self, k):
        return (f'<diagram id="fig{k}" name={quoteattr(self.name)}><mxGraphModel dx="1400" dy="900" grid="0" '
                f'gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="0" pageScale="1" '
                f'math="0" shadow="0"><root><mxCell id="0"/><mxCell id="1" parent="0"/>{"".join(self.cells)}'
                f'</root></mxGraphModel></diagram>')


def B(title, sub=""):
    return f"<b>{title}</b>" + (f'<br><font style="font-size:13px">{sub}</font>' if sub else "")


pages: list[Page] = []

# =============================================================================
# Fig. 1 - block-level architecture
# =============================================================================
p = Page("arch_blocks"); pages.append(p)
t_data = p.node("ior", 0, 105, 150, 30, "i_data")
t_pv = p.node("ior", 0, 150, 150, 30, "i_pixel_valid")
t_wv = p.node("ior", 0, 305, 150, 30, "i_weight_valid")
t_sel = p.node("ior", 0, 400, 150, 30, "i_select_kernel")
lane = p.node("group", 780, 40, 830, 400, "Kernel lane  × K")
inreg = p.node("reg", 190, 90, 120, 290, B("Input<br>registers"))
lb = p.node("mem", 370, 95, 150, 90, B("Line buffer", "N−1 rows"))
wg = p.node("win", 580, 95, 150, 90, B("Window", "N × N"))
mac = p.node("dsp", 820, 95, 150, 90, B("MAC", "DSP48E1"))
rs = p.node("reg", 1020, 95, 150, 90, B("Round &amp;<br>saturate"))
relu = p.node("opt", 1220, 95, 150, 90, B("ReLU", "optional"))
fifo = p.node("mem", 1420, 95, 150, 90, B("Output<br>FIFO"))
kr = p.node("reg", 820, 300, 150, 90, B("Kernel<br>register"))
o_f = p.node("iol", 1650, 110, 220, 30, "o_feature[k]")
o_v = p.node("iol", 1650, 150, 260, 30, "o_valid, o_frame_done")
p.edge(t_data, inreg, en=(0, 0.103))
p.edge(t_pv, inreg, extra=DASH, en=(0, 0.255))
p.edge(t_wv, inreg, extra=DASH, en=(0, 0.79))
p.edge(t_sel, kr, extra=DASH, pts=[(790, 415), (790, 367)], en=(0, 0.75))
p.edge(inreg, lb, "pixel", ex=(1, 0.124), en=(0, 0.344))
p.edge(inreg, wg, "live row", ex=(0.5, 0), en=(0.5, 0), pts=[(250, 60), (655, 60)])
p.edge(lb, wg, "rows", ex=(1, 0.344), en=(0, 0.344))
p.edge(wg, mac, "window", ex=(1, 0.344), en=(0, 0.344))
p.edge(kr, mac, "weights", ex=(0.5, 0), en=(0.5, 1))
p.edge(inreg, kr, "weight", ex=(1, 0.862), en=(0, 0.4))
p.edge(mac, rs, "sum", ex=(1, 0.344), en=(0, 0.344))
p.edge(rs, relu, ex=(1, 0.344), en=(0, 0.344))
p.edge(relu, fifo, ex=(1, 0.344), en=(0, 0.344))
p.edge(fifo, o_f, ex=(1, 0.344))
for a, b_ in ((inreg, lb), (lb, wg), (wg, mac), (mac, rs), (rs, relu), (relu, fifo)):
    p.edge(a, b_, extra=DASH, ex=(1, 0.255 if a == inreg else 0.767), en=(0, 0.767))
p.edge(fifo, o_v, extra=DASH, ex=(1, 0.767))

# =============================================================================
# Fig. 2 - register-level microarchitecture, generic in N, W and K
# =============================================================================
p = Page("arch_detailed"); pages.append(p)
PANEL = ("rounded=1;arcSize=4;whiteSpace=wrap;html=1;verticalAlign=top;align=left;spacingLeft=10;"
         "spacingTop=4;fontStyle=1;fontSize=15;" + FONT)
ST.update({
    "p_single": PANEL + "fillColor=#eef4fc;strokeColor=#6c8ebf;fontColor=#1f3a5f;",
    "p_row": PANEL + "fillColor=#fff8e6;strokeColor=#d6b656;fontColor=#7a5c00;",
    "p_tree": PANEL + "fillColor=#fdeeee;strokeColor=#b85450;fontColor=#8a2f2c;",
})
p.node("group", 160, 60, 170, 900, "① Input")
p.node("group", 360, 60, 440, 560, "② Line buffer")
p.node("group", 830, 60, 380, 560, "③ Window")
mac_g = p.node("group", 1240, 60, 760, 740, "④ MAC · one option generated per lane")
p.node("group", 2030, 60, 250, 560, "⑤ Round &amp; saturate")
p.node("group", 2310, 60, 170, 560, "⑥ ReLU")
p.node("group", 2510, 60, 440, 560, "⑦ Output FIFO")
p.node("group", 1240, 820, 760, 170, "Kernel register (per lane)")
# inputs
i_data = p.node("ior", 0, 150, 140, 30, "i_data")
i_pv = p.node("ior", 0, 260, 140, 30, "i_pixel_valid")
i_wv = p.node("ior", 0, 860, 140, 30, "i_weight_valid")
i_sel = p.node("ior", 0, 925, 140, 30, "i_select_kernel")
r_data = p.node("reg", 180, 145, 130, 40, "r_data")
r_pwe = p.node("reg", 180, 255, 130, 40, "pixel WE")
r_wwe = p.node("reg", 180, 855, 130, 40, "weight WE")
p.edge(i_data, r_data)
p.edge(i_pv, r_pwe, extra=DASH)
p.edge(i_wv, r_wwe, extra=DASH)
# line buffer: N-1 SRL banks
bank0 = p.node("mem", 400, 130, 300, 50, B("SRL bank 0", "W taps × 8 bit"))
p.node("io", 560, 183, 40, 40, "⋮", "fontSize=20;")
bankL = p.node("mem", 400, 230, 300, 50, B("SRL bank N−2", "W taps × 8 bit"))
colc = p.node("reg", 390, 380, 150, 50, "column count")
ring = p.node("reg", 580, 380, 190, 50, "row ring (W FF)")
rrdy = p.node("reg", 390, 490, 150, 50, "rows_ready")
fend = p.node("reg", 580, 490, 190, 50, "frame end")
# window: N x N registers
cells = {}
for r, yy, rn in ((2, 100, "N−1"), (1, 190, "1"), (0, 260, "0")):
    for c, cn in enumerate(("0", "…", "N−1")):
        cells[r, c] = p.node("win", 845 + c * 115, yy, 95, 44, "…" if cn == "…" else f"({rn},{cn})", "fontSize=13;")
p.node("io", 845, 146, 325, 40, "⋮", "fontSize=20;")
colw = p.node("reg", 845, 380, 150, 50, "column count")
wval = p.node("reg", 1030, 380, 160, 50, "window valid")
kand = p.node("logic", 1030, 490, 160, 50, "∧ kernel ready")
p.edge(r_data, bank0, "pixel", ex=(1, 0.5), en=(0, 0.5), pts=[(350, 165), (350, 155)])
p.edge(r_data, cells[2, 0], ex=(1, 0.5), en=(0, 0.5), pts=[(340, 165), (340, 40), (825, 40), (825, 122)])
p.edge(bank0, cells[1, 0], ex=(1, 0.5), en=(0, 0.5), pts=[(760, 155), (760, 212)])
p.edge(bank0, bankL, ex=(0.5, 1), en=(0.5, 0))
p.edge(bankL, cells[0, 0], ex=(1, 0.5), en=(0, 0.5), pts=[(780, 255), (780, 282)])
for r in range(3):
    for c in range(2):
        p.edge(cells[r, c], cells[r, c + 1])
p.edge(r_pwe, colc, "write enable", extra=DASH, ex=(1, 0.5), en=(0, 0.5), pts=[(350, 275), (350, 405)])
p.edge(colc, ring, "row done", extra=DASH)
p.edge(ring, rrdy, extra=DASH, ex=(0.5, 1), en=(0.5, 0), pts=[(675, 460), (465, 460)])
p.edge(ring, fend, extra=DASH, ex=(0.5, 1), en=(0.5, 0))
p.edge(colw, wval, extra=DASH)
p.edge(rrdy, wval, extra=DASH, ex=(0.5, 1), en=(0.5, 1), pts=[(465, 580), (1110, 580)])
p.edge(wval, kand, extra=DASH, ex=(0.5, 1), en=(0.5, 0))
p.edge(cells[1, 2], mac_g, "window", ex=(1, 0.5), en=(0, 0.2054))
p.edge(kand, mac_g, "valid", extra=DASH, ex=(1, 0.5), en=(0, 0.6149))
# round stage A is the common destination of the three MAC options
sa = p.node("reg", 2060, 200, 190, 60, B("stage A", "value · guard bit"))


def mini_dsp(x, y, w, h, name, op=10, d=24):
    p.node("dsp", x, y, w, h, name, "verticalAlign=top;align=right;spacingRight=5;spacingTop=1;fontSize=11;fontStyle=1;")
    m = p.node("op", x + 7, y + op, d, d, "×", "fontSize=14;")
    a = p.node("op", x + w - d - 12, y + op, d, d, "+", "fontSize=14;")
    p.edge(m, a)
    return m, a


def to_round(src_id, y, label=""):
    p.edge(src_id, sa, label, ex=(1, 0.5), en=(0, 0.5), pts=[(2005, y), (2005, 230)])


# MAC_SEL 3: single cascade - skew registers, one PCOUT -> PCIN chain
p.node("p_single", 1260, 100, 720, 200, "MAC_SEL 3 · single cascade")
p.node("small", 1560, 104, 400, 24, "tap e: e skew FF + AREG", "align=right;")
prev_add = None
for slot, name, skew in ((0, "0", "0 FF"), (1, "1", "1 FF"), (2, "2", "2 FF"), (4, "N²−1", "N²−1 FF")):
    x = 1300 + slot * 130
    m, a = mini_dsp(x, 180, 110, 70, name, op=30)
    sk = p.node("reg", x - 11, 132, 60, 28, skew, "fontSize=12;")
    p.edge(sk, m, ex=(0.5, 1), en=(0.5, 0))
    if prev_add:
        p.edge(prev_add, a, "…" if slot == 4 else "", extra=CASC, ex=(0.5, 1), en=(0.5, 1),
               pts=[(px + 86, 242), (x + 86, 242)])
    prev_add, px = a, x
p.node("io", 1690, 132, 60, 28, "…", "fontSize=16;")
to_round(prev_add, 222, "sum")
# MAC_SEL 2: one cascade per window row, row sums, fabric tree
p.node("p_row", 1260, 320, 720, 220, "MAC_SEL 2 · row chains")
row_bars = []
for yr, rl in ((355, "0"), (455, "N−1")):
    p.node("iol", 1268, yr + 22, 70, 24, f"row {rl}", "fontSize=13;")
    prev_add = None
    for c, (x, name) in enumerate(((1340, f"{rl},0"), (1450, f"{rl},1"), (1580, f"{rl},N−1"))):
        m, a = mini_dsp(x, yr, 90, 60, name, op=24, d=22)
        if prev_add:
            p.edge(prev_add, a, "…" if c == 2 else "", extra=CASC, ex=(0.5, 1), en=(0.5, 1),
                   pts=[(px + 67, yr + 53), (x + 67, yr + 53)])
        prev_add, px = a, x
    bar = p.node("bar", 1690, yr + 15, 20, 40, "")
    p.edge(prev_add, bar, ex=(1, 0.5), en=(0, 0.5))
    row_bars.append(bar)
p.node("io", 1340, 418, 330, 30, "⋮", "fontSize=18;")
p.node("small", 1640, 322, 330, 24, "row sums", "align=right;")
ra = p.node("add", 1760, 422, 36, 36, "+", "fontSize=18;")
rb = p.node("bar", 1815, 415, 20, 50, "")
p.edge(row_bars[0], ra, ex=(1, 0.5), en=(0, 0.25), pts=[(1735, 390), (1735, 431)])
p.edge(row_bars[1], ra, ex=(1, 0.5), en=(0, 0.75), pts=[(1735, 490), (1735, 449)])
p.edge(ra, rb)
p.node("small", 1730, 482, 230, 24, "⌈log₂N⌉ registered levels")
to_round(rb, 440)
# MAC_SEL 1: parallel multipliers and a registered binary tree
p.node("p_tree", 1260, 560, 720, 220, "MAC_SEL 1 · multiplier array + adder tree")
dsp_ids = [p.node("dsp", 1280, 595 + k * 38, 170, 30, f"DSP {k} · A/B → M → P", "fontSize=12;fontStyle=1;")
           for k in range(4)]
p.node("io", 1280, 743, 170, 30, "⋮", "fontSize=18;")
add1 = p.node("add", 1510, 604, 30, 30, "+", "fontSize=15;")
add2 = p.node("add", 1510, 680, 30, 30, "+", "fontSize=15;")
bar1 = p.node("bar", 1560, 599, 16, 40, "")
bar2 = p.node("bar", 1560, 675, 16, 40, "")
add3 = p.node("add", 1610, 642, 30, 30, "+", "fontSize=15;")
bar3 = p.node("bar", 1660, 637, 16, 40, "")
add4 = p.node("add", 1760, 642, 30, 30, "+", "fontSize=15;")
bar4 = p.node("bar", 1810, 637, 16, 40, "")
p.edge(dsp_ids[0], add1, ex=(1, 0.5), en=(0, 0.25))
p.edge(dsp_ids[1], add1, ex=(1, 0.5), en=(0, 0.75))
p.edge(dsp_ids[2], add2, ex=(1, 0.5), en=(0, 0.25))
p.edge(dsp_ids[3], add2, ex=(1, 0.5), en=(0, 0.75))
p.edge(add1, bar1)
p.edge(add2, bar2)
p.edge(bar1, add3, ex=(1, 0.5), en=(0, 0.25))
p.edge(bar2, add3, ex=(1, 0.5), en=(0, 0.75))
p.edge(add3, bar3)
p.edge(bar3, add4, "…")
p.edge(add4, bar4)
p.node("small", 1610, 700, 260, 24, "⌈log₂N²⌉ registered levels")
to_round(bar4, 657)
# kernel register
wand = p.node("logic", 1260, 860, 140, 90, "WE ∧<br>(sel = k)")
wchain = p.node("reg", 1420, 875, 280, 60, "w[N²−1] → … → w[0]")
wcnt = p.node("reg", 1720, 875, 120, 60, "load count")
wrdy = p.node("logic", 1860, 875, 120, 60, "ready")
p.edge(r_wwe, wand, extra=DASH, ex=(1, 0.5), en=(0, 0.1667))
p.edge(i_sel, wand, extra=DASH, ex=(1, 0.5), en=(0, 0.889))
p.edge(wand, wchain, extra=DASH)
p.edge(wchain, wcnt, extra=DASH)
p.edge(wcnt, wrdy, extra=DASH)
p.edge(wchain, mac_g, "weights", ex=(0.5, 0), en=(0.421, 1))
p.edge(wrdy, kand, extra=DASH, ex=(0.5, 1), en=(1, 0.5), pts=[(1920, 1005), (1222, 1005), (1222, 515)])
# round & saturate: stage A, round half up, clamp only when reachable, stage B
radd = p.node("add", 2125, 290, 60, 60, "+")
p.node("small", 2190, 305, 75, 30, "guard", "align=left;")
clamp = p.node("opt", 2060, 380, 190, 50, B("clamp", "only if reachable"))
sb = p.node("reg", 2060, 470, 190, 60, B("stage B", "16-bit feature"))
p.edge(sa, radd, ex=(0.5, 1), en=(0.5, 0))
p.edge(radd, clamp, ex=(0.5, 1), en=(0.5, 0))
p.edge(clamp, sb, ex=(0.5, 1), en=(0.5, 0))
p.edge(sa, clamp, "overflow", extra=DASH, ex=(1, 0.5), en=(1, 0.5), pts=[(2272, 230), (2272, 405)])
# ReLU: relu_unit when ENABLE_RELU = 1, a wire otherwise
p.node("small", 2312, 300, 166, 26, "ENABLE_RELU = 1")
relub = p.node("opt", 2325, 330, 140, 70, B("relu_unit", "sign ? 0 : x"))
p.edge(sb, relub, ex=(1, 0.3), en=(0, 0.5), pts=[(2295, 488), (2295, 365)])
p.node("small", 2312, 528, 166, 40, "bypass wire<br>ENABLE_RELU = 0")
# FIFO
ram = p.node("mem", 2540, 130, 200, 110, B("RAM", "LUTRAM or BRAM"))
wptr = p.node("reg", 2780, 130, 150, 44, "write ptr")
rptr = p.node("reg", 2780, 196, 150, 44, "read ptr")
pref = p.node("reg", 2540, 400, 180, 50, "prefilled")
lastw = p.node("reg", 2540, 500, 180, 50, "last written")
odat = p.node("reg", 2760, 300, 170, 50, "o_data")
oval = p.node("reg", 2760, 400, 170, 50, "o_valid")
done = p.node("logic", 2760, 500, 170, 50, "frame done")
p.edge(relub, ram, ex=(1, 0.5), en=(0, 0.5), pts=[(2495, 365), (2495, 185)])
p.edge(sb, ram, ex=(1, 0.8), en=(0, 0.5), pts=[(2495, 518), (2495, 185)])
p.edge(wptr, ram, extra=DASH, ex=(0, 0.5), en=(1, 0.3))
p.edge(rptr, ram, extra=DASH, ex=(0, 0.5), en=(1, 0.75))
p.edge(ram, odat, ex=(0.5, 1), en=(0.5, 0), pts=[(2640, 275), (2845, 275)])
p.edge(pref, oval, extra=DASH)
p.edge(lastw, done, extra=DASH)
o1 = p.node("iol", 2980, 310, 200, 30, "o_feature[k]")
o2 = p.node("iol", 2980, 410, 200, 30, "o_valid")
o3 = p.node("iol", 2980, 510, 200, 30, "o_frame_done")
p.edge(odat, o1)
p.edge(oval, o2)
p.edge(done, o3)
# frame-end delay line
dly = p.node("reg", 580, 1030, 2170, 50,
             B("frame-end delay line", "LAST_DELAY flip-flops = MAC latency + 2 (+1 with ReLU)"))
p.edge(fend, dly, extra=DASH, ex=(0.5, 1), en=(0.0438, 0))
p.edge(dly, lastw, "last mark", extra=DASH, ex=(0.9447, 0), en=(0.5, 1))
# latency strip
lat = [("input", "+1", 160, 170), ("line buffer", "0", 360, 440), ("window", "+1", 830, 380),
       ("MAC", "+N²+2  ·  +N+⌈log₂N⌉+2  ·  +⌈log₂N²⌉+3", 1240, 760), ("round", "+2", 2030, 250),
       ("ReLU", "0 / +1", 2310, 170), ("FIFO", "+1", 2510, 440)]
p.node("ior", 0, 1125, 150, 30, "<b>latency</b>")
for name, cyc, x, w in lat:
    p.node("logic", x, 1120, w, 40, f"{name}  <b>{cyc}</b>",
           "fontSize=15;arcSize=30;fillColor=#f5f5f5;strokeColor=#bbbbbb;")
# legend
p.node("group", 0, 1185, 2950, 115, "", "fillColor=#ffffff;")
for k, (kind, text) in enumerate((("reg", "register / counter"), ("win", "window register"),
                                  ("mem", "SRL · LUTRAM · BRAM"), ("dsp", "DSP48E1"), ("logic", "logic"),
                                  ("opt", "optional (ENABLE_RELU)"))):
    x = 40 + k * 480
    p.node(kind, x, 1200, 50, 30, "")
    p.node("iol", x + 65, 1200, 400, 30, text)
for k, (kind, text) in enumerate((("p_single", "MAC_SEL 3 · single cascade"), ("p_row", "MAC_SEL 2 · row chains"),
                                  ("p_tree", "MAC_SEL 1 · multiplier array + tree"))):
    x = 40 + k * 480
    p.node(kind, x, 1252, 50, 30, "")
    p.node("iol", x + 65, 1252, 400, 30, text)
for k, (sty, text) in enumerate((("", "data"), (DASH, "valid / control"), (CASC, "PCOUT → PCIN cascade"))):
    x = 40 + (3 + k) * 480
    a_ = p.node("io", x, 1267, 1, 1, "")
    b_ = p.node("io", x + 50, 1267, 1, 1, "")
    p.edge(a_, b_, extra=sty)
    p.node("iol", x + 65, 1252, 400, 30, text)

# =============================================================================
# Fig. 3 - kernel register
# =============================================================================
p = Page("kernel_register"); pages.append(p)
en_t = p.node("ior", 0, 85, 170, 30, "WE, i_select_kernel")
wand = p.node("logic", 200, 70, 180, 60, "WE ∧ (sel = k)")
cnt = p.node("reg", 470, 70, 170, 60, "load count")
cmp_ = p.node("logic", 720, 70, 130, 60, "= N² ?")
rdy = p.node("iol", 890, 85, 120, 30, "o_ready")
p.edge(en_t, wand, extra=DASH)
p.edge(wand, cnt, "count", extra=DASH)
p.edge(cnt, cmp_)
p.edge(cmp_, rdy)
grp = p.node("group", 180, 200, 1070, 110, "", "fillColor=none;")
w_in = p.node("ior", 0, 240, 150, 30, "weight")
chain = []
for i in range(9):
    chain.append(p.node("reg", 200 + i * 115, 225, 90, 60, B(f"w[{8 - i}]")))
p.edge(w_in, chain[0])
for i in range(8):
    p.edge(chain[i], chain[i + 1])
p.edge(wand, grp, "shift", extra=DASH, ex=(0.5, 1), en=(0.103, 0))
w_out = p.node("io", 535, 380, 400, 30, "o_weights  →  MAC (B port)")
p.edge(grp, w_out, ex=(0.5, 1), en=(0.5, 0))

# =============================================================================
# Fig. 4 - line buffer
# =============================================================================
p = Page("line_buffer"); pages.append(p)
pix = p.node("ior", 0, 80, 140, 30, "pixel")
bank0 = p.node("mem", 240, 160, 420, 64, B("SRL bank 0", "32 taps × 8 bit · 1 row delay"))
bank1 = p.node("mem", 240, 290, 420, 64, B("SRL bank 1", "32 taps × 8 bit · 2 row delay"))
wgen = p.node("win", 980, 60, 190, 330, B("Window<br>generator"))
p.edge(pix, wgen, "row 2 (live)", en=(0, 0.106))
p.edge(pix, bank0, ex=(1, 0.5), en=(0, 0.5), pts=[(190, 95), (190, 192)])
p.edge(bank0, wgen, "row 1", ex=(1, 0.5), en=(0, 0.4))
p.edge(bank0, bank1, ex=(1, 0.5), en=(0, 0.5), pts=[(720, 192), (720, 255), (200, 255), (200, 322)])
p.edge(bank1, wgen, "row 0", ex=(1, 0.5), en=(0, 0.794))
we = p.node("ior", 0, 465, 140, 30, "write enable")
colc = p.node("reg", 220, 450, 170, 60, "column count")
ring = p.node("reg", 520, 450, 210, 60, B("row ring", "32 FF, one-hot"))
rrdy = p.node("reg", 800, 450, 170, 60, "rows_ready")
fend = p.node("reg", 800, 550, 170, 60, "frame end")
p.edge(we, colc, extra=DASH)
p.edge(colc, ring, "row done", extra=DASH)
p.edge(ring, rrdy, extra=DASH)
p.edge(ring, fend, extra=DASH, ex=(0.5, 1), en=(0, 0.5), pts=[(625, 580)])
p.edge(rrdy, wgen, extra=DASH, ex=(1, 0.5), en=(0.5, 1), pts=[(1075, 480)])
fo = p.node("iol", 1010, 565, 220, 30, "output FIFO")
p.edge(fend, fo, extra=DASH)

# =============================================================================
# Fig. 5 - window generator
# =============================================================================
p = Page("window_generator"); pages.append(p)
rows = {}
for r, yy, txt in ((2, 70, "row 2 (live)"), (1, 150, "row 1"), (0, 230, "row 0")):
    t = p.node("ior", 0, yy + 13, 170, 30, txt)
    prev = t
    for c in range(3):
        cc = p.node("win", 220 + c * 140, yy, 110, 56, B(f"({r},{c})"))
        p.edge(prev, cc)
        prev = cc
    rows[r] = prev
ow = p.node("io", 740, 140, 180, 70, B("o_window", "9 × 8 bit"))
for r in (2, 1, 0):
    p.edge(rows[r], ow, en=(0, 0.5))
we = p.node("ior", 0, 365, 170, 30, "write enable")
rd = p.node("ior", 0, 425, 170, 30, "row done → clear")
rr = p.node("ior", 0, 485, 170, 30, "rows_ready")
colc = p.node("reg", 220, 360, 180, 60, "column count")
cond = p.node("logic", 460, 440, 220, 60, "rows_ready ∧ count ≥ N−1")
wv = p.node("reg", 740, 440, 180, 60, "window valid")
ov = p.node("iol", 960, 455, 120, 30, "o_valid")
p.edge(we, colc, extra=DASH, en=(0, 0.3))
p.edge(rd, colc, extra=DASH, en=(0, 0.8), pts=[(195, 440), (195, 408)])
p.edge(colc, cond, extra=DASH, ex=(1, 0.5), en=(0.25, 0), pts=[(515, 390)])
p.edge(rr, cond, extra=DASH, en=(0, 0.75))
p.edge(cond, wv)
p.edge(wv, ov)

# =============================================================================
# Line buffer and window operation (redrawn from the team's line-buffer sheet)
# =============================================================================
p = Page("line_buffer_window"); pages.append(p)
pix = p.node("ior", 0, 30, 110, 30, "pixel")
bank0 = p.node("mem", 200, 120, 380, 56, B("SRL bank 0", "1 row delay"))
bank1 = p.node("mem", 200, 250, 380, 56, B("SRL bank 1", "2 rows delay"))
X = {0: 700, 1: 920, 2: 1140}
Y0 = {0: 280, 1: 190, 2: 100}
ff = {}
for r in (0, 1, 2):
    for k, c in enumerate((2, 1, 0)):
        ff[r, c] = p.node("reg", X[r], Y0[r] + k * 95, 90, 50, B(f"({r},{c})"))
    p.edge(ff[r, 2], ff[r, 1])
    p.edge(ff[r, 1], ff[r, 0])
p.edge(pix, ff[2, 2], ex=(1, 0.5), en=(0.5, 0), pts=[(1185, 45)])
p.edge(pix, bank0, ex=(1, 0.5), en=(0, 0.5), pts=[(150, 45), (150, 148)])
p.edge(bank0, ff[1, 2], ex=(1, 0.5), en=(0.5, 0), pts=[(965, 148)])
p.edge(bank0, bank1, ex=(1, 0.5), en=(0, 0.5), pts=[(630, 148), (630, 215), (170, 215), (170, 278)])
p.edge(bank1, ff[0, 2], ex=(1, 0.5), en=(0.5, 0), pts=[(745, 278)])
for r in (0, 1, 2):
    for c, dx in ((0, 45), (1, 120), (2, 185)):
        t = p.node("io", X[r] + dx - 30, 600, 60, 26, f"({r},{c})", "fontSize=14;")
        if c == 0:
            p.edge(ff[r, 0], t, ex=(0.5, 1), en=(0.5, 0))
        else:
            p.edge(ff[r, c], t, ex=(1, 0.5), en=(0.5, 0), pts=[(X[r] + dx, Y0[r] + (2 - c) * 95 + 25)])
p.node("head", 700, 640, 700, 30, "window taps (row, column) → MAC")
GX, GY, S, W = 1500, 110, 44, 8
wr0, wc0 = 2, 3
cur = (wr0 + 2, wc0 + 2)
for i in range(W):
    for j in range(W):
        inwin = wr0 <= i < wr0 + 3 and wc0 <= j < wc0 + 3
        if inwin:
            extra = "fillColor=#f8cecc;strokeColor=#b85450;"
        elif (i, j) <= cur:
            extra = "fillColor=#d5e8d4;strokeColor=#82b366;"
        else:
            extra = "fillColor=#ffffff;strokeColor=#bbbbbb;"
        if (i, j) == cur:
            extra += "strokeWidth=3;strokeColor=#c0392b;"
        p.node("reg", GX + j * S, GY + i * S, S, S, f"{i - wr0},{j - wc0}" if inwin else "",
               extra + "fontSize=12;fontStyle=1;")
p.node("head", GX, GY - 50, W * S, 40, "image, raster order")
p.node("small", GX - 20, GY + W * S + 10, W * S + 40, 50, "green: written · red: current window<br>bold: newest pixel")

# =============================================================================
# DSP48E1 slice (new figure, before the MAC architectures)
# =============================================================================
p = Page("dsp48e1_slice"); pages.append(p)
p.node("frame", 170, 20, 860, 380, "DSP48E1")
a_t = p.node("ior", 0, 90, 150, 30, "pixel, 9 b")
b_t = p.node("ior", 0, 290, 150, 30, "weight, 8 b")
aa = p.node("reg", 230, 80, 100, 50, B("AREG"))
bb = p.node("reg", 230, 280, 100, 50, B("BREG"))
mul = p.node("op", 400, 165, 80, 80, "×")
mm = p.node("reg", 540, 180, 100, 50, B("MREG"))
add = p.node("op", 710, 165, 80, 80, "+")
pp = p.node("reg", 860, 180, 100, 50, B("PREG"))
p_t = p.node("iol", 1070, 190, 200, 30, "<b>PCOUT</b>", "fontColor=#c0392b;")
pcin = p.node("red", 680, 440, 140, 30, "PCIN")
p.edge(a_t, aa)
p.edge(aa, mul, ex=(1, 0.5), en=(0.5, 0), pts=[(440, 105)])
p.edge(b_t, bb)
p.edge(bb, mul, ex=(1, 0.5), en=(0.5, 1), pts=[(440, 305)])
p.edge(mul, mm)
p.edge(mm, add)
p.edge(add, pp)
p.edge(pp, p_t, extra=CASC)
p.edge(pcin, add, extra=CASC, ex=(0.5, 0), en=(0.5, 1))

# =============================================================================
# DSP48E1 slice with its internal registers (single cascade and row chains)
# =============================================================================
def dsp_detail(p, x, y, name, head):
    """One DSP48E1 as used by the cascades; returns (AREG, BREG, post-adder, PREG)."""
    p.node("dsp", x, y, 350, 150, f"<b>{name}</b>",
           "verticalAlign=top;align=left;spacingLeft=12;spacingTop=4;fontSize=13;")
    areg = p.node("reg", x + 14, y + 85, 70, 28, "AREG", "fontSize=13;")
    breg = p.node("reg", x + 90, y + 32, 70, 28, "BREG", "fontSize=13;")
    mul = p.node("op", x + 110, y + 84, 30, 30, "×", "fontSize=16;")
    mreg = p.node("reg", x + 160, y + 85, 70, 28, "MREG", "fontSize=13;")
    add = p.node("op", x + 248, y + 84, 30, 30, "+", "fontSize=16;")
    preg = p.node("reg", x + 290, y + 85, 54, 28, "PREG", "fontSize=12;")
    p.edge(areg, mul)
    p.edge(breg, mul, ex=(0.5, 1), en=(0.5, 0))
    p.edge(mul, mreg)
    p.edge(mreg, add)
    p.edge(add, preg)
    p.node("small", x + 12, y + 120, 220, 24, "P = M" if head else "P = PCIN + M", "align=left;")
    return areg, breg, add, preg


def tap_into(p, X, Y, e, skew, areg, breg):
    """Pixel tap e through `skew` flip-flops into AREG, weight e into BREG."""
    pin = p.node("io", X, Y + 30, 90, 26, f"p[{e}]", "fontSize=15;")
    if skew == 0:
        p.edge(pin, areg, ex=(0.5, 1), en=(0, 0.5), pts=[(X + 45, Y + 99)])
    else:
        sk = p.node("reg", X, Y + 85, 90, 28, f"{skew} FF", "fontSize=14;")
        p.edge(pin, sk, ex=(0.5, 1), en=(0.5, 0))
        p.edge(sk, areg)
    win = p.node("io", X + 210, Y - 34, 70, 26, f"w[{e}]", "fontSize=15;")
    p.edge(win, breg, ex=(0.5, 1), en=(0.5, 0))


# =============================================================================
# Fig. 6 - single DSP cascade (all N^2 slices in one PCOUT -> PCIN chain)
# =============================================================================
p = Page("mac_single_chain"); pages.append(p)
prev = None
for e in range(9):
    row, slot = divmod(e, 3)
    X, Y = slot * 500, 60 + row * 280
    areg, breg, add, preg = dsp_detail(p, X + 120, Y, f"DSP48E1 #{e}", e == 0)
    tap_into(p, X, Y, e, e, areg, breg)
    if prev:
        pp, pX, pY, pslot = prev
        if pslot < 2:
            p.edge(pp, add, "PCOUT → PCIN", extra=CASC + "fontColor=#c0392b;", ex=(1, 0.5), en=(0.5, 1),
                   pts=[(pX + 478, pY + 99), (pX + 478, pY + 172), (X + 383, pY + 172)])
        else:
            p.edge(pp, add, "PCOUT → PCIN", extra=CASC + "fontColor=#c0392b;", ex=(1, 0.5), en=(0.5, 0),
                   pts=[(pX + 478, pY + 99), (pX + 478, pY + 205), (X + 383, pY + 205)])
    prev = (preg, X, Y, slot)
out = p.node("iol", 1500, 620 + 84, 170, 30, B("o_sum", "20 bit"))
p.edge(prev[0], out)

# =============================================================================
# Fig. 7 - row DSP chains + pipelined adder tree
# =============================================================================
p = Page("mac_row_chain"); pages.append(p)
row_out = []
for r in range(3):
    Y = 60 + r * 280
    p.node("head", 0, Y - 50, 200, 26, f"window row {r}", "align=left;")
    prev = None
    for c in range(3):
        X = c * 500
        e = 3 * r + c
        areg, breg, add, preg = dsp_detail(p, X + 120, Y, f"DSP ({r},{c})", c == 0)
        tap_into(p, X, Y, e, c, areg, breg)
        if prev:
            pp, pX = prev
            p.edge(pp, add, "PCOUT → PCIN", extra=CASC + "fontColor=#c0392b;", ex=(1, 0.5), en=(0.5, 1),
                   pts=[(pX + 478, Y + 99), (pX + 478, Y + 172), (X + 383, Y + 172)])
        prev = (preg, X)
    row_out.append(prev[0])
p.node("group", 1540, 20, 440, 860, "Pipelined adder tree (fabric)")
p.node("head", 1550, 60, 200, 30, "stage 1 · 19 b")
p.node("head", 1760, 60, 200, 30, "stage 2 · 20 b")
a1 = p.node("add", 1600, 267, 64, 64, "+")
r1 = p.node("bar", 1700, 264, 34, 70, "")
pr = p.node("bar", 1700, 684, 34, 70, "")
a2 = p.node("add", 1820, 477, 64, 64, "+")
r2 = p.node("bar", 1920, 474, 34, 70, "")
p.edge(row_out[0], a1, "18 b", ex=(1, 0.5), en=(0, 0.25), pts=[(1570, 159), (1570, 283)])
p.edge(row_out[1], a1, "18 b", ex=(1, 0.5), en=(0, 0.75), pts=[(1570, 439), (1570, 315)])
p.edge(a1, r1)
p.edge(row_out[2], pr, "18 b")
p.edge(r1, a2, ex=(1, 0.5), en=(0, 0.25), pts=[(1780, 299), (1780, 493)])
p.edge(pr, a2, ex=(1, 0.5), en=(0, 0.75), pts=[(1780, 719), (1780, 525)])
p.edge(a2, r2)
o = p.node("iol", 2000, 489, 170, 40, B("o_sum", "20 bit"))
p.edge(r2, o)

# =============================================================================
# Fig. 8 - multiplier array + pipelined adder tree
# =============================================================================
p = Page("mac_tree"); pages.append(p)
YS = [60 + i * 78 for i in range(9)]
mul = [p.node("dsp", 40, y, 170, 58, B(f"p{i} × w{i}"), "fontSize=15;") for i, y in enumerate(YS)]
centers = [y + 29 for y in YS]
p.node("head", 40, 10, 170, 30, "DSP multipliers")
for k, x in enumerate((340, 560, 780, 1000)):
    p.node("head", x - 40, 10, 190, 30, f"stage {k + 1} · {17 + k} b")


def level(prev, prev_c, x_op):
    """Pair neighbours; an odd last operand is only registered (pass-through)."""
    nodes, cs = [], []
    for i in range(0, len(prev), 2):
        if i + 1 < len(prev):
            cy = (prev_c[i] + prev_c[i + 1]) / 2
            a = p.node("add", x_op, cy - 26, 52, 52, "+")
            p.edge(prev[i], a, en=(0, 0.2))
            p.edge(prev[i + 1], a, en=(0, 0.8))
            r = p.node("bar", x_op + 80, cy - 30, 28, 60, "")
            p.edge(a, r)
        else:
            cy = prev_c[i]
            r = p.node("bar", x_op + 80, cy - 30, 28, 60, "")
            p.edge(prev[i], r)
        nodes.append(r)
        cs.append(cy)
    return nodes, cs


n, c = level(mul, centers, 320)
n, c = level(n, c, 540)
n, c = level(n, c, 760)
n, c = level(n, c, 980)
o = p.node("iol", 1130, c[0] - 25, 170, 50, B("o_sum", "20 bit"))
p.edge(n[0], o)

# =============================================================================
# Fig. 9 - MAC selection
# =============================================================================
p = Page("mac_selection"); pages.append(p)
st = p.node("term", 510, 0, 220, 60, B("N, K"))
d1 = p.node("dec", 520, 110, 200, 110, "K = 1 ?")
d2 = p.node("dec", 200, 260, 200, 110, "N ≤ 3 ?")
d3 = p.node("dec", 200, 420, 200, 110, "N ≤ 8 ?")
d4 = p.node("dec", 810, 240, 260, 150, "N ≤ 8 and<br>N²·K ≤ 180 ?")
o1 = p.node("dsp", 460, 285, 320, 60, B("Single DSP cascade"))
o2 = p.node("dsp", 460, 560, 320, 60, B("Row DSP chains"), "fillColor=#fff2cc;strokeColor=#d6b656;")
o3 = p.node("dsp", 460, 680, 320, 60, B("Multiplier array + adder tree"), "fillColor=#f8cecc;strokeColor=#b85450;")
p.edge(st, d1)
p.edge(d1, d2, "yes", ex=(0, 0.5), en=(0.5, 0), pts=[(300, 165)])
p.edge(d1, d4, "no", ex=(1, 0.5), en=(0.5, 0), pts=[(940, 165)])
p.edge(d2, o1, "yes")
p.edge(d2, d3, "no")
p.edge(d3, o2, "yes", ex=(0.5, 1), en=(0, 0.5), pts=[(300, 590)])
p.edge(d3, o3, "no", ex=(0, 0.5), en=(0, 0.5), pts=[(140, 475), (140, 710)])
p.edge(d4, o2, "yes", ex=(0.5, 1), en=(1, 0.5), pts=[(940, 590)])
p.edge(d4, o3, "no", ex=(1, 0.5), en=(1, 0.5), pts=[(1120, 315), (1120, 710)])

# =============================================================================
# Fig. 10 - round and saturate
# =============================================================================
p = Page("round_saturate"); pages.append(p)
sin = p.node("ior", 0, 105, 150, 30, "sum [19:0]")
sa = p.node("reg", 200, 70, 200, 100, B("stage A", "value [19:4]<br>guard [3]"))
ad = p.node("add", 490, 90, 60, 60, "+")
cl = p.node("opt", 630, 80, 180, 80, B("clamp", "only if reachable"))
sb = p.node("reg", 880, 70, 200, 100, B("stage B"))
sout = p.node("iol", 1120, 105, 170, 30, "feature [15:0]")
p.edge(sin, sa)
p.edge(sa, ad, ex=(1, 0.3), en=(0, 0.5), pts=[(445, 100), (445, 120)])
p.edge(sa, ad, "guard", ex=(1, 0.8), en=(0.5, 1), pts=[(520, 150)])
p.edge(ad, cl)
p.edge(cl, sb)
p.edge(sb, sout)
vin = p.node("ior", 0, 245, 150, 30, "i_valid")
v1 = p.node("reg", 200, 230, 200, 60, "valid")
v2 = p.node("reg", 880, 230, 200, 60, "valid")
vout = p.node("iol", 1120, 245, 170, 30, "o_valid")
p.edge(vin, v1, extra=DASH)
p.edge(v1, v2, extra=DASH)
p.edge(v2, vout, extra=DASH)

# =============================================================================
# Fig. 11 - output FIFO
# =============================================================================
p = Page("output_fifo"); pages.append(p)
fin = p.node("ior", 0, 180, 140, 30, "feature")
fv = p.node("ior", 0, 80, 140, 30, "valid")
fl = p.node("ior", 0, 575, 140, 30, "last mark")
wptr = p.node("reg", 190, 65, 180, 60, "write pointer")
ram = p.node("mem", 440, 150, 240, 120, B("RAM", "64 × 16 (LUTRAM)"))
odat = p.node("reg", 760, 180, 180, 60, "o_data")
fout = p.node("iol", 990, 195, 170, 30, "o_feature")
rptr = p.node("reg", 470, 320, 180, 60, "read pointer")
empty = p.node("logic", 190, 320, 180, 60, "empty: rd = wr")
pref = p.node("reg", 190, 440, 180, 60, "prefilled")
lastw = p.node("reg", 190, 560, 180, 60, "last written")
rd = p.node("logic", 470, 440, 180, 60, "read = prefilled ∧ ¬empty", "fontSize=14;")
ov = p.node("reg", 760, 440, 180, 60, "o_valid")
dn = p.node("logic", 470, 560, 180, 60, "done = prefilled ∧ last ∧ empty", "fontSize=14;")
clr = p.node("reg", 760, 680, 180, 60, "clear")
out2 = p.node("iol", 990, 455, 170, 30, "o_valid")
out3 = p.node("iol", 990, 575, 200, 30, "o_frame_done")
p.edge(fv, wptr, extra=DASH)
p.edge(fin, ram, "write", en=(0, 0.375))
p.edge(wptr, ram, "address", extra=DASH, ex=(1, 0.5), en=(0.5, 0), pts=[(560, 95)])
p.edge(ram, odat)
p.edge(odat, fout)
p.edge(rptr, ram, "address", extra=DASH, ex=(0.5, 0), en=(0.5, 1))
p.edge(empty, rd, extra=DASH, ex=(1, 0.5), en=(0, 0.3), pts=[(420, 350), (420, 458)])
p.edge(pref, rd, extra=DASH)
p.edge(rd, ov)
p.edge(ov, out2)
p.edge(rd, rptr, "+1", extra=DASH, ex=(0.5, 0), en=(0.5, 1))
p.edge(fl, lastw)
p.edge(lastw, dn)
p.edge(dn, clr, ex=(0.5, 1), en=(0, 0.5), pts=[(560, 710)])
p.edge(dn, out3)
p.edge(clr, wptr, "clear", extra=DASH, ex=(1, 0.5), en=(0.5, 0), pts=[(1220, 710), (1220, 20), (280, 20)])

# =============================================================================
# Fig. 12 - implicit control state machine
# =============================================================================
p = Page("control_fsm"); pages.append(p)
RIGHT = "align=right;spacingRight=14;"
p.node("group", 260, 215, 950, 155, "input side", RIGHT)
p.node("group", 260, 425, 950, 155, "output side", RIGHT)
rst = p.node("term", 20, 60, 190, 70, B("RESET", "power-up / abort"))
load = p.node("state", 290, 60, 200, 70, B("LOAD KERNEL"))
fl_ = p.node("state", 290, 260, 200, 70, B("FILL LINES"))
fw = p.node("state", 620, 260, 200, 70, B("FILL WINDOW"))
sm = p.node("state", 950, 260, 200, 70, B("STREAM"))
pf = p.node("state", 290, 480, 200, 70, B("PREFILL"))
ou = p.node("state", 620, 480, 200, 70, B("OUTPUT"))
dr = p.node("state", 950, 480, 200, 70, B("DRAIN"))
p.edge(rst, load, "rst_n high")
p.edge(load, fl_, "all lanes ready")
p.edge(fl_, fw, "row N−1")
p.edge(fw, sm, "column N−1")
p.edge(sm, fw, "next row", ex=(0.5, 0), en=(0.5, 0), pts=[(1050, 240), (720, 240)])
p.edge(sm, pf, "features", extra=DASH, ex=(0.5, 1), en=(0.5, 0), pts=[(1050, 400), (390, 400)])
p.edge(pf, ou, "58 stored")
p.edge(ou, dr, "last pixel in")
p.edge(dr, fl_, "o_frame_done · next frame", extra="strokeColor=#2e7d32;strokeWidth=2.5;fontColor=#2e7d32;fontStyle=1;",
       ex=(0.5, 1), en=(0, 0.5), pts=[(1050, 630), (230, 630), (230, 295)])
p.edge(dr, load, "new kernel", extra=DASH, ex=(1, 0.5), en=(1, 0.5), pts=[(1260, 515), (1260, 95)])

# =============================================================================
# Fig. 23 - board demonstration on the PYNQ-Z2
# =============================================================================
p = Page("board_demo"); pages.append(p)
BIDIR = "startArrow=block;startFill=1;"
p.node("io", 0, 120, 250, 50, B("Host PC", "browser · Jupyter"))
pc = p.node("laptop", 40, 180, 170, 110)
p.node("board", 330, 20, 1250, 670, "PYNQ-Z2 board")
p.node("soc", 370, 70, 980, 460, "Zynq-7020 SoC")
ps = p.node("ps", 400, 120, 360, 380, "Processing system")
p.node("pl", 790, 120, 530, 380, "Programmable logic")
arm = p.node("logic", 430, 170, 300, 64, B("2 × ARM Cortex-A9", "Linux + PYNQ"))
drv = p.node("logic", 430, 280, 300, 64, B("conv_demo.py", "driver + golden model"))
gp0 = p.node("logic", 430, 390, 300, 56, B("AXI GP0 master"))
axi = p.node("logic", 820, 170, 230, 64, B("AXI interconnect", "AXI4-Lite"))
wrap = p.node("reg", 820, 300, 210, 110, B("conv_axi_lite", "registers · pixel feed<br>result BRAM"))
core = p.node("dsp", 1100, 300, 190, 110, B("conv_system", "3 × 3 · 9 DSP48E1"))
eth = p.node("logic", 400, 590, 110, 60, B("Ethernet"))
sd = p.node("mem", 525, 590, 110, 60, B("microSD"))
ddr = p.node("mem", 650, 590, 110, 60, B("DDR3"))
ledp = p.node("pl", 1390, 300, 150, 130, "LEDs", "fontSize=16;")
for k in range(4):
    p.node("led", 1405 + k * 32, 375, 24, 24)
p.edge(arm, drv)
p.edge(drv, gp0)
p.edge(gp0, axi, ex=(1, 0.5), en=(0, 0.5), pts=[(775, 418), (775, 202)])
p.edge(axi, wrap, "0x43C00000", ex=(0.4, 1), en=(0.5, 0), pts=[(912, 267), (925, 267)])
p.edge(wrap, core, extra=BIDIR)
p.edge(wrap, ledp, extra=DASH, ex=(0.5, 1), en=(0.5, 1), pts=[(925, 470), (1465, 470)])
p.edge(pc, eth, "Ethernet", ex=(0.5, 1), en=(0, 0.5), pts=[(125, 620)], extra=BIDIR)
p.edge(eth, ps, extra=BIDIR, ex=(0.5, 0), en=(0.153, 1))
p.edge(sd, ps, "boot", extra=DASH, ex=(0.5, 0), en=(0.5, 1))
p.edge(ddr, ps, extra=BIDIR, ex=(0.5, 0), en=(0.847, 1))
steps = ["load overlay", "write kernel", "stream pixels", "frame done", "read features", "compare with model"]
prev = None
for k, s in enumerate(steps):
    b = p.node("logic", 330 + k * 212, 730, 180, 56, f"<b>{k + 1}</b>  {s}", "fontSize=14;arcSize=30;fillColor=#f5f5f5;")
    if prev:
        p.edge(prev, b)
    prev = b

# =============================================================================
# Verification flow
# =============================================================================
p = Page("verification_flow"); pages.append(p)
p.node("group", 0, 0, 460, 640, "SystemVerilog")
p.node("group", 500, 0, 1520, 640, "Python golden model")
tb = p.node("reg", 40, 70, 380, 80, B("conv_system_tb", "self-checking · built-in reference"))
dut0 = p.node("dsp", 40, 300, 380, 80, B("conv_system", "all three MAC architectures"))
p.edge(tb, dut0, "stimulus", ex=(0.3, 1), en=(0.3, 0))
p.edge(dut0, tb, "outputs", ex=(0.7, 0), en=(0.7, 1))
p.node("pass", 40, 550, 380, 60, "<b>40 configs × 11 tests</b>  pass")
img = p.node("logic", 540, 70, 190, 70, B("images, kernels"))
con = p.node("logic", 780, 70, 170, 70, B("contract.py"))
stim = p.node("doc", 1000, 75, 160, 60, "stimulus.txt")
p.node("group", 1210, 40, 790, 340, "conv_image_tb  (QuestaSim)", "fillColor=#fdfaf0;strokeColor=#d6b656;")
rd = p.node("logic", 1240, 90, 200, 60, B("read_stimulus"))
drv = p.node("logic", 1240, 210, 200, 80, B("drivers", "push_weights<br>stream_frames"))
clk = p.node("logic", 1500, 90, 200, 50, "clk_gen · reset", "fontSize=14;")
dut = p.node("dsp", 1500, 205, 200, 90, B("conv_system", "DUT"))
mon = p.node("logic", 1760, 210, 210, 80, B("monitor", "capture features<br>check o_frame_done"))
wr = p.node("logic", 1760, 90, 210, 60, B("write_results"))
p.node("small", 1230, 305, 760, 50,
       "in: i_data · i_pixel_valid · i_weight_valid · i_select_kernel<br>out: o_feature[K] · o_valid · o_frame_done")
feat = p.node("doc", 1000, 425, 160, 60, "features.txt")
ref = p.node("logic", 540, 420, 190, 70, B("reference.py", "golden model"))
har = p.node("logic", 780, 420, 190, 70, B("harness.py", "bit-exact compare"))
p.edge(img, con)
p.edge(con, stim)
p.edge(stim, rd, ex=(1, 0.5), en=(0, 0.25), pts=[(1200, 105)])
p.edge(rd, drv)
p.edge(drv, dut)
p.edge(clk, dut, extra=DASH)
p.edge(dut, mon)
p.edge(mon, wr)
p.edge(wr, feat, ex=(1, 0.5), en=(1, 0.5), pts=[(2005, 120), (2005, 455)])
p.edge(img, ref)
p.edge(feat, har)
p.edge(ref, har)
p.node("pass", 540, 550, 430, 60, "<b>unit tests</b>  94 pass")
reg_ = p.node("pass", 1000, 550, 990, 60, "<b>hardware regression</b>  61 pass · 289 328 features")
p.edge(har, reg_, ex=(0.5, 1), en=(0.5, 0), pts=[(875, 525), (1495, 525)])

# =============================================================================
# conv_system_tb structure
# =============================================================================
p = Page("tb_structure"); pages.append(p)
p.node("group", 0, 0, 1480, 640, "conv_system_tb")
p.node("logic", 30, 50, 1420, 44,
       "<b>parameters</b>   WINDOW_SIZE · INPUT_SIZE · NUM_KERNELS · ENABLE_RELU · STALL · ROUND_MODE",
       "fillColor=#f5f5f5;strokeColor=#bbbbbb;fontSize=15;")
tests = p.node("reg", 30, 130, 300, 470,
               "<b>test sequence</b><br><br>box_filter<br>tap_order<br>signed_weights<br>dynamic_range<br>"
               "relu_clamp<br>relu_negative_range<br>unused_select<br><br>stream_back_to_back<br>"
               "stream_idle_gaps<br>stream_kernel_reload<br><br>abort_reset",
               "fontSize=15;verticalAlign=top;spacingTop=14;")
stim = p.node("logic", 400, 130, 280, 100, B("stimulus", "fill_image · set_uniform<br>set_rotated · load_random_kernels"))
drv = p.node("logic", 400, 300, 280, 100, B("drivers", "push_weights<br>stream_frame (STALL gaps)"))
clk = p.node("logic", 760, 150, 240, 60, "clk_gen · apply_reset", "fontSize=14;")
dut = p.node("dsp", 760, 305, 240, 90, B("conv_system", "DUT"))
mon = p.node("logic", 1080, 300, 370, 100, B("monitor", "o_feature[k] vs expected<br>o_frame_done on the last feature"))
model = p.node("mem", 400, 480, 280, 110, B("reference model", "model_mac → model_round_saturate<br>→ model_relu"))
q = p.node("doc", 760, 500, 240, 70, "tb_expected[K][$]")
sbd = p.node("pass", 1080, 495, 370, 80, B("scoreboard", "[PASS] / [FAIL] per test · $finish code"))
p.edge(tests, stim, ex=(1, 0.1064), en=(0, 0.5))
p.edge(tests, drv, ex=(1, 0.4681), en=(0, 0.5))
p.edge(stim, drv, "image, kernels", ex=(0.5, 1), en=(0.5, 0))
p.edge(stim, model, ex=(1, 0.75), en=(0.85, 0), pts=[(720, 205), (720, 450), (638, 450)])
p.edge(clk, dut, extra=DASH)
p.edge(drv, dut)
p.edge(dut, mon)
p.edge(model, q)
p.edge(q, mon, "expected", ex=(1, 0.5), en=(0, 0.75), pts=[(1040, 535), (1040, 375)])
p.edge(mon, sbd, "errors", ex=(0.5, 1), en=(0.5, 0))

OUT.write_text('<mxfile host="gen_figures_v3">' + "".join(pg.xml(k) for k, pg in enumerate(pages)) + "</mxfile>",
               encoding="utf-8")
print(f"wrote {OUT} with {len(pages)} pages: " + ", ".join(pg.name for pg in pages))
