"""Build slides.pptx: the final-round deck as an editable PowerPoint file.

Same content, order, colours and logos as slides.typ / slides.pdf. Text is real
text (editable), figures are the PNGs of docs/report/figures.

    cd docs/presentation
    python make_pptx.py            # needs: pip install python-pptx

Speaker notes are added in PowerPoint, not here: a notes page written by python-pptx
makes PowerPoint load that slide empty.

In text, *...* marks bold blue emphasis and `...` marks code.
"""
import re
import struct
from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Emu, Inches, Pt

HERE = Path(__file__).resolve().parent
FIG = HERE.parent / "report" / "figures"

CRIMSON = RGBColor(0xB9, 0x0B, 0x2E)   # IEEE SSCS
IEEE = RGBColor(0x00, 0x66, 0x99)      # IEEE blue
INK = RGBColor(0x1A, 0x1A, 0x1A)
MUTED = RGBColor(0x55, 0x59, 0x5E)
TINT = RGBColor(0xF3, 0xF6, 0xF9)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
PINK = RGBColor(0xF6, 0xD9, 0xDF)
FONT = "Segoe UI"
MONO = "Consolas"

W, H = 13.333, 7.5          # 16:9, inches
MX = 0.6                    # side margin
BW = W - 2 * MX             # body width
TOP, BOTTOM = 1.32, 6.88    # body area

prs = Presentation()
prs.slide_width, prs.slide_height = Inches(W), Inches(H)
BLANK = prs.slide_layouts[6]
page_no = [0]


# ------------------------------------------------------------------ helpers
def png_size(path):
    with open(path, "rb") as f:
        f.seek(16)
        return struct.unpack(">II", f.read(8))


def runs(par, text, size, color=INK, bold=False):
    """Add text to a paragraph; *x* = bold blue, `x` = monospace."""
    for part in re.split(r"(\*[^*]+\*|`[^`]+`)", text):
        if not part:
            continue
        r = par.add_run()
        f = r.font
        f.size, f.name, f.bold = Pt(size), FONT, bold
        f.color.rgb = color
        if part[0] == "*" and part[-1] == "*":
            inner = part[1:-1]
            if inner[0] == "`":                 # *`code`*
                inner, f.name = inner.strip("`"), MONO
            r.text, f.bold = inner, True
            f.color.rgb = IEEE if color == INK else color
        elif part[0] == "`":
            r.text, f.name = part[1:-1], MONO
        else:
            r.text = part


def textbox(slide, x, y, w, h, anchor=MSO_ANCHOR.TOP):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    return tf


def text(slide, s, x, y, w, h, size, color=INK, bold=False, align=PP_ALIGN.LEFT,
         anchor=MSO_ANCHOR.TOP):
    tf = textbox(slide, x, y, w, h, anchor)
    p = tf.paragraphs[0]
    p.alignment = align
    runs(p, s, size, color, bold)
    return tf


def bullets(slide, items, x=MX, y=TOP, w=BW, h=None, size=21, gap=10):
    """A bulleted list with crimson round bullets."""
    tf = textbox(slide, x, y, w, h or (BOTTOM - y))
    for i, item in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.space_after = Pt(gap)
        p.line_spacing = 1.05
        pPr = p._p.get_or_add_pPr()
        pPr.set("marL", str(Inches(0.36)))
        pPr.set("indent", str(-Inches(0.36)))
        clr = pPr.makeelement(qn("a:buClr"), {})
        clr.append(clr.makeelement(qn("a:srgbClr"), {"val": "B90B2E"}))
        pPr.append(clr)
        pPr.append(pPr.makeelement(qn("a:buSzPct"), {"val": "80000"}))
        pPr.append(pPr.makeelement(qn("a:buFont"), {"typeface": "Arial"}))
        pPr.append(pPr.makeelement(qn("a:buChar"), {"char": "●"}))
        runs(p, item, size)
    return tf


def picture(slide, rel, x, y, w, h, valign="middle"):
    """Place a figure inside the box (x, y, w, h), keeping its aspect ratio."""
    path = FIG / rel if not Path(rel).is_absolute() else Path(rel)
    pw, ph = png_size(path)
    scale = min(w / pw, h / ph)
    iw, ih = pw * scale, ph * scale
    top = y + (h - ih) / 2 if valign == "middle" else y
    return slide.shapes.add_picture(str(path), Inches(x + (w - iw) / 2), Inches(top),
                                    Inches(iw), Inches(ih))


def card(slide, value, label, x, y, w, h=1.25, accent=IEEE):
    """One big number with a readable label."""
    box = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    box.adjustments[0] = 0.06
    box.fill.solid()
    box.fill.fore_color.rgb = TINT
    box.line.fill.background()
    box.shadow.inherit = False
    text(slide, value, x, y + 0.12, w, 0.6, 32, accent, True, PP_ALIGN.CENTER)
    text(slide, label, x, y + 0.76, w, 0.4, 16, INK, False, PP_ALIGN.CENTER)


def table(slide, rows, x, y, w, widths, size=16.5, bold_last=False, row_h=0.42):
    """Reference table: blue header row, light zebra rows."""
    shape = slide.shapes.add_table(len(rows), len(rows[0]), Inches(x), Inches(y), Inches(w),
                                   Inches(row_h * len(rows)))
    tbl = shape.table
    tblPr = shape._element.graphic.graphicData.tbl.tblPr
    style = tblPr.find(qn("a:tableStyleId"))
    if style is not None:
        style.text = "{5940675A-B579-460E-94D1-54222C63F5DA}"   # "No Style, Table Grid"
    total = sum(widths)
    for c, cw in enumerate(widths):
        tbl.columns[c].width = Inches(w * cw / total)
    for r, row in enumerate(rows):
        tbl.rows[r].height = Inches(row_h)
        for c, val in enumerate(row):
            cell = tbl.cell(r, c)
            cell.margin_left = cell.margin_right = Inches(0.12)
            cell.margin_top = cell.margin_bottom = Inches(0.04)
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            cell.fill.solid()
            cell.fill.fore_color.rgb = IEEE if r == 0 else (TINT if r % 2 == 0 else WHITE)
            p = cell.text_frame.paragraphs[0]
            head = r == 0
            last = bold_last and r == len(rows) - 1
            runs(p, val, size, WHITE if head else (IEEE if last else INK), head or last)
            tcPr = cell._tc.get_or_add_tcPr()
            for side in ("a:lnL", "a:lnR", "a:lnT", "a:lnB"):
                ln = tcPr.makeelement(qn(side), {"w": "6350"})
                fill = ln.makeelement(qn("a:solidFill"), {})
                fill.append(fill.makeelement(qn("a:srgbClr"), {"val": "D3DCE4"}))
                ln.append(fill)
                tcPr.append(ln)
    return shape


def slide(title):
    """A content slide: title, SSCS logo, crimson rule, footer."""
    s = prs.slides.add_slide(BLANK)
    page_no[0] += 1
    text(s, title, MX, 0.30, BW - 1.8, 0.72, 29, IEEE, True, anchor=MSO_ANCHOR.BOTTOM)
    s.shapes.add_picture(str(HERE / "logo_sscs_egypt.png"), Inches(W - MX - 1.52), Inches(0.50), height=Inches(0.49))
    rule = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(MX), Inches(1.10), Inches(W - MX), Inches(1.10))
    rule.line.color.rgb = CRIMSON
    rule.line.width = Pt(2.25)
    text(s, "ARA Silicon · Ain Shams University", MX, 7.04, 4, 0.28, 12, MUTED)
    text(s, "IEEE SSCS Egypt · 2026 Student Design Competition", 4.2, 7.04, W - 8.4, 0.28, 12, MUTED,
         align=PP_ALIGN.CENTER)
    text(s, str(page_no[0]), W - MX - 1, 7.04, 1, 0.28, 12, MUTED, align=PP_ALIGN.RIGHT)
    return s


def figure_slide(title, fig, items, ratio=1.35, fig_left=True, gap=0.35):
    """Figure on one side, points on the other."""
    s = slide(title)
    fw = (BW - gap) * ratio / (ratio + 1)
    tw = BW - gap - fw
    fx, tx = (MX, MX + fw + gap) if fig_left else (MX + tw + gap, MX)
    picture(s, fig, fx, TOP, fw, BOTTOM - TOP - 0.1)
    bullets(s, items, tx, TOP + 0.05, tw)
    return s


def block(s, x, y, w, h, color):
    r = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    r.fill.solid()
    r.fill.fore_color.rgb = color
    r.line.fill.background()
    r.shadow.inherit = False
    return r


# ------------------------------------------------------------------ 1. title
s = prs.slides.add_slide(BLANK)
page_no[0] += 1
s.shapes.add_picture(str(HERE / "logo_sscs_egypt.png"), Inches(0.63), Inches(0.27), height=Inches(0.92))
s.shapes.add_picture(str(HERE / "logo_ieee_egypt.png"), Inches(W - 0.63 - 2.0), Inches(0.38), height=Inches(0.68))
block(s, 0, 1.43, W, 3.52, CRIMSON)
text(s, "2026 Student Design Competition", 0.63, 1.85, 11, 0.4, 17, PINK)
text(s, "FPGA-Based Edge-AI Vision Accelerator", 0.63, 2.35, 12, 0.75, 38, WHITE, True)
text(s, "for N×N CNN Convolution", 0.63, 3.08, 12, 0.75, 38, WHITE, True)
text(s, "Architecture · Verification · FPGA Implementation", 0.63, 4.15, 12, 0.5, 21, PINK)
tf = textbox(s, 0.63, 5.25, 12, 0.6)
runs(tf.paragraphs[0], "ARA Silicon", 27, IEEE, True)
runs(tf.paragraphs[0], "    Ain Shams University", 20, MUTED)
for i, (name, dept) in enumerate((("Ahmed Ashraf", "Computer and Systems Engineering"),
                                  ("Rana Ayman", "Computer and Systems Engineering"),
                                  ("Ammar Ahmed", "Electronics and Communications Engineering"))):
    text(s, name, 0.63 + 3.6 * i, 5.95, 4.6, 0.42, 21)
    text(s, dept, 0.63 + 3.6 * i, 6.38, 4.6, 0.35, 15, MUTED)

# ------------------------------------------------------------------ 2. design principle
s = slide("Design principle: follow the Figure of Merit")
bullets(s, [
    "In the Figure of Merit, flip-flops are *free*, one DSP costs 50 LUTs, one BRAM costs 100",
    "*Our principle:* do every addition *inside the DSP slices*, and make the *most efficient use of memory*",
    "*One generic RTL:* any kernel size (2×2 to 17×17), image size and number of kernels; ReLU optional",
    "*MAC architecture selected automatically* from the kernel size and the number of kernels",
    "*FIFO memory selected automatically:* LUTRAM or BRAM, whichever costs less in the FoM "
    "— our build needs only LUTRAM",
])

# ------------------------------------------------------------------ 3. results
s = slide("Results at a glance")
text(s, "*Build:* 3×3 kernel · 32×32 image · one kernel · 8-bit data · 16-bit output", MX, TOP, BW, 0.45, 21)
cards = [("78 LUTs", "0.15 % of the device", CRIMSON), ("9 DSPs", "0 BRAM · all arithmetic in DSPs", IEEE),
         ("305.6 MHz", "Fmax · 250 MHz timing met", IEEE), ("110.6 mW", "total power, routed SAIF", IEEE),
         ("1 px / cycle", "sustained throughput", IEEE), ("0.01712", "Figure of Merit", CRIMSON)]
cw, cg = (BW - 2 * 0.25) / 3, 0.25
for i, (v, l, a) in enumerate(cards):
    card(s, v, l, MX + (i % 3) * (cw + cg), TOP + 0.6 + (i // 3) * 1.42, cw, accent=a)
bullets(s, [
    "*0 mismatches* against the golden model in 307 328 output features",
    "*All five bonus features*; frames stream *without a reset*, with *input stall support*",
], y=4.95)

# ------------------------------------------------------------------ 4. architecture
s = slide("Architecture: one streaming pipeline")
picture(s, "diagrams/arch_blocks.png", MX + 0.4, TOP, BW - 0.8, 3.85)
bullets(s, [
    "*Shared front end:* input registers, line buffer, N×N window",
    "*One lane per kernel:* weights, MAC, rounding, ReLU, output FIFO",
], y=5.4)

# ------------------------------------------------------------------ 5. datapath widths
s = slide("Datapath: bit widths, overflow, saturation")
bullets(s, [
    "8-bit pixel × 8-bit weight = *16-bit product*",
    "Sum of N² products: the accumulator grows by ⌈log₂N²⌉ bits → *20 bits, exact*",
    "Drop the same ⌈log₂N²⌉ bits and *round half up* → 16-bit output",
    "Largest result is 255 × 128 = *32 640*, below 32 768 for *every N*: *overflow cannot happen*",
    "The saturation clamp is generated only if a width change makes it reachable",
], h=3.5, gap=8)
picture(s, "diagrams/round_saturate.png", MX + 2.3, 4.85, BW - 4.6, 1.95)

# ------------------------------------------------------------------ 6. line buffer
s = slide("Line buffer and sliding window")
picture(s, "diagrams/line_buffer_window.png", MX + 0.7, TOP, BW - 1.4, 4.05)
half = (BW - 0.4) / 2
bullets(s, ["N−1 rows in *shift-register LUTs*", "The live row is *never stored*"], MX, 5.62, half)
bullets(s, ["Row position: a *one-hot ring*", "Whole line buffer: *22 LUTs, 0 BRAM*"], MX + half + 0.4, 5.62, half)

# ------------------------------------------------------------------ 7. control
figure_slide("Control: an implicit FSM", "diagrams/control_fsm.png", [
    "*No FSM state register*: a *valid bit* travels with the data",
    "States are decoded from *counters the datapath already has*",
    "*Stall:* when `i_pixel_valid` drops, the front end *holds*; the MAC finishes what is inside "
    "and the FIFO covers the gap",
    "After `o_frame_done`: next frame, *no reset*",
])

# ------------------------------------------------------------------ 9-11. three MACs
figure_slide("One DSP48E1 slice", "diagrams/dsp48e1_slice.png", [
    "P = PCIN + A × B: the *post-adder accumulates*",
    "AREG, BREG, MREG, PREG *all enabled*",
    "Tap e is delayed e+1 cycles by *skew flip-flops*",
    "Flip-flops are free in the FoM",
], ratio=1.4)

figure_slide("MAC 1: multiplier array + adder tree", "diagrams/mac_tree.png", [
    "*N² parallel DSP multipliers*",
    "A *pipelined binary adder tree* in fabric",
    "Simple, but the tree costs LUTs: *143 at 3×3*",
    "The only one that continues *past 220 DSPs*, with LUT multipliers",
    "Used for *large kernels*, up to 17×17",
], ratio=1.3)

figure_slide("MAC 2: row DSP chains", "diagrams/mac_row_chain.png", [
    "*One DSP chain per window row*",
    "Row additions move *inside the DSPs*; only a small tree remains",
    "3×3 MAC: *43 LUTs*",
    "Scales to *196 DSPs* (14×14)",
    "Used for *N = 4 to 8*, and for several kernels",
], ratio=1.4)

figure_slide("MAC 3: single DSP cascade", "diagrams/mac_single_chain.png", [
    "All N² slices in *one PCOUT → PCIN chain*",
    "*Every addition is inside a DSP*: the 3×3 MAC is *2 LUTs*",
    "Cost: delay flip-flops grow as N⁴ — *free in the FoM*",
    "Used for *N ≤ 3*, one kernel: *the competition build*",
], ratio=1.4)

# ------------------------------------------------------------------ 12-13. selection, sweep
figure_slide("One of the three is selected automatically", "diagrams/mac_selection.png", [
    "Decided at *elaboration* from the kernel size N and kernel count K",
    "Only the *selected* architecture is built",
    "`MAC_ARCH` can force any one",
    "The limits are *parameters*",
    "All three verified *bit-exact*",
], ratio=1.15)

figure_slide("Why three: kernel sizes 2×2 to 17×17", "charts/sweep_fom_ratio.png", [
    "*35 routed builds* at 160 MHz",
    "Single cascade wins for *N ≤ 4*",
    "Row chains win for *N = 5 to 11*",
    "The tree wins from *N = 12* and is the only one that reaches 17×17",
])

# ------------------------------------------------------------------ 14. rounding
figure_slide("Rounding: half up, and no saturation logic", "charts/saturation_headroom.png", [
    "*Round half up:* 78 LUTs, 305.6 MHz",
    "Round half to even: 93 LUTs, 278.9 MHz",
    "*Same RMS error*, 0.29 LSB; bias only 1/32 LSB",
    "Always building the clamp: 99 LUTs, FoM −11 %",
    "We keep the *smallest stage that is still exact*",
], ratio=1.0, fig_left=False)

# ------------------------------------------------------------------ 15. one pixel per cycle
s = slide("One pixel per cycle, frames without reset")
picture(s, "waves/xsim_power_rowedge.png", MX + 1.5, TOP, BW - 3.0, 3.6)
bullets(s, [
    "The window is invalid for N−1 pixels at each row edge",
    "A *prefill FIFO of 58 features* hides the gaps: `o_valid` never drops",
    "`o_frame_done` marks the last feature; the next frame needs *no reset*",
], y=5.08, gap=7)

# ------------------------------------------------------------------ 16. full architecture
s = slide("Full architecture: the datapath in detail")
picture(s, "diagrams/arch_detailed.png", MX, TOP, BW, BOTTOM - TOP)

# ------------------------------------------------------------------ 17-18. verification
s = slide("Verification: two independent references")
picture(s, "diagrams/verification_flow.png", MX + 1.0, TOP, BW - 2.0, 3.85)
vc = [("40 × 11", "SV configs × tests", IEEE), ("100", "Python unit tests", IEEE),
      ("87", "regression frames", IEEE), ("0", "mismatches", CRIMSON)]
cw = (BW - 3 * 0.2) / 4
for i, (v, l, a) in enumerate(vc):
    card(s, v, l, MX + i * (cw + 0.2), 5.45, cw, accent=a)

figure_slide("Hardware versus golden model: bit for bit", "verif/cli_inspection.png", [
    "Golden model in *Python / NumPy*",
    "128×128 images, *3 kernels in parallel*",
    "*47 628 features* per image, every one identical",
    "Kernel sizes 2×2 to 11×11, 1 to 16 kernels",
    "*307 328 features compared, 0 mismatches*",
], ratio=1.15)

# ------------------------------------------------------------------ Figure of Merit
s = slide("Figure of Merit")
text(s, "FoM  =  Throughput  /  ( Power × ( LUT + 50 · DSP + 100 · BRAM ) )", MX, TOP + 0.1, BW, 0.7, 27, INK, True,
     PP_ALIGN.CENTER, MSO_ANCHOR.MIDDLE)
bullets(s, [
    "*Throughput:* 1 pixel per clock cycle, sustained",
    "*Area:* 78 LUT + 50 × 9 DSP + 100 × 0 BRAM = *528*",
    "*Power:* 110.6 mW, from a routed SAIF (checkerboard + Sobel-Y)",
    "*FoM* = 1 / (0.1106 W × 528) = *0.01712*",
    "Second workload, bars + Sobel-X: 119.9 mW, FoM *0.01579*",
], y=TOP + 1.25)

# ------------------------------------------------------------------ 19. FPGA results
figure_slide("FPGA results on the Zynq-7020", "vivado/device_view.png", [
    "*Utilization:* 78 LUT · 521 FF · 9 DSP · 0 BRAM",
    "*Timing:* 250 MHz met, WNS +0.728 ns",
    "*Fmax:* 305.6 MHz",
    "*Power:* 110.6 mW, of which 6.2 mW dynamic",
    "*Latency:* 16 cycles per pixel",
    "*Throughput:* 1 pixel per cycle = 250 Mpx/s",
    "*FoM:* 0.01712",
], ratio=0.85)

# ------------------------------------------------------------------ bonus
s = slide("All five bonus features")
bullets(s, [
    "*ReLU activation* — per kernel, parameter `ENABLE_RELU`",
    "*One output pixel per cycle* — 900 features in 900 consecutive cycles",
    "*Multiple kernels* — 1 to 16 in parallel, sharing one window",
    "*Board demonstration* — PYNQ-Z2 overlay with a Python driver",
    "*Edge-detection demo* — Sobel and Laplacian on 128×128 images",
    "Beyond the brief: *frames back to back without a reset*, and one RTL for every kernel size "
    "from 2×2 to 17×17",
])

# ------------------------------------------------------------------ 22. trade-offs
s = slide("Trade-offs, and what we would improve")
half = (BW - 0.5) / 2
text(s, "Trade-offs we made", MX, TOP + 0.02, half, 0.5, 24, CRIMSON, True)
bullets(s, [
    "*Flip-flops instead of LUTs:* +7 % FoM",
    "*No saturation logic:* proven unreachable",
    "*Shift registers, not BRAM,* for the line buffer",
    "*Reported at 250 MHz:* lower FoM than 150 MHz, but best energy per pixel",
], MX, TOP + 0.7, half)
text(s, "What we would improve", MX + half + 0.5, TOP + 0.02, half, 0.5, 24, CRIMSON, True)
bullets(s, [
    "*Tune the architecture limits* for each target clock",
    "*AXI-Stream / DMA* on the board instead of register writes",
    "*Multi-channel and multi-layer* convolution",
    "*Formal verification* of each block",
], MX + half + 0.5, TOP + 0.7, half)

# ------------------------------------------------------------------ 23. conclusion
s = slide("Conclusion")
bullets(s, [
    "*All arithmetic in DSP slices:* a 3×3 MAC in 2 LUTs",
    "*78 LUTs, 9 DSPs, 0 BRAM* at *305.6 MHz*, one pixel per cycle",
    "*FoM 0.01712* from routed, SAIF-based power",
    "*One generic RTL,* three MAC architectures, 2×2 to 17×17",
    "*Bit-exact* against the golden model, all five bonuses",
], h=3.6)
text(s, "Thank you — questions?", MX, 5.75, BW, 0.8, 36, CRIMSON, True, PP_ALIGN.CENTER, MSO_ANCHOR.MIDDLE)

# ------------------------------------------------------------------ backup
s = prs.slides.add_slide(BLANK)
page_no[0] += 1
block(s, 0, 0, W, H, IEEE)
text(s, "Backup slides", 0, 0, W, H, 44, WHITE, True, PP_ALIGN.CENTER, MSO_ANCHOR.MIDDLE)

figure_slide("Backup: board demonstration on the PYNQ-Z2", "diagrams/board_demo.png", [
    "*AXI4-Lite wrapper* around the accelerator",
    "*Python driver* and golden model in a Jupyter notebook",
    "*Every frame is compared* against the reference",
    "Simulated end to end first: *0 mismatches*",
], ratio=1.4)

s = slide("Backup: latency of one pixel")
table(s, [["Stage", "Cycles"], ["Input registers", "1"], ["Line buffer", "0"], ["Window generator", "1"],
          ["MAC, single cascade (2 + N²)", "11"], ["Round and saturate", "2"], ["ReLU (when enabled: 1)", "0"],
          ["Output FIFO", "1"], ["Pipeline depth", "16"]], MX, TOP + 0.05, 6.3, [3.4, 1], bold_last=True)
bullets(s, [
    "First feature after *142 cycles* (line fill + FIFO prefill)",
    "Whole 32×32 frame in *1041 cycles*",
    "Then *one feature every cycle*",
], MX + 6.7, TOP + 0.05, BW - 6.7)

s = slide("Backup: alternatives we built and rejected")
table(s, [["Approach", "LUT", "FF", "DSP", "FoM"],
          ["Baseline: multipliers + fabric adder tree", "243", "442", "9", "0.01061"],
          ["DSP row chains", "149", "335", "9", "0.01284"],
          ["*Single 9-DSP cascade (chosen)*", "*68*", "*456*", "*9*", "*0.01520*"],
          ["Double MAC, two products per DSP", "429", "919", "5", "0.01023"],
          ["DSP multi-pumping × 3", "262", "380", "3", "0.00503"],
          ["Fabric multipliers, no DSP", "933", "—", "0", "fails timing"]],
      MX, TOP + 0.05, BW, [5.6, 1, 1, 1, 1.9])
bullets(s, ["Every candidate was *verified first*, then measured on the same flow"], y=4.75)

s = slide("Backup: where the LUTs go")
table(s, [["Module", "LUT", "FF"], ["`line_buffer`", "22", "39"], ["`window_generator`", "3", "75"],
          ["`kernel_register`", "5", "76"], ["`mac_single_chain`", "2", "226"], ["`round_saturate`", "3", "35"],
          ["`output_fifo`", "43", "32"], ["`conv_system` top", "0", "38"], ["Total", "78", "521"]],
      MX, TOP + 0.05, 6.3, [3.2, 1, 1], bold_last=True)
bullets(s, [
    "The MAC is *2 LUTs*: nine multiply-adds live in DSP slices",
    "The FIFO is the largest block: it buys *one pixel per cycle*",
    "*94 % of the power* is the static floor of the idle Zynq",
], MX + 6.7, TOP + 0.05, BW - 6.7)

s = slide("Backup: kernel-size sweep, LUTs and resources")
picture(s, "charts/sweep_resources.png", MX, TOP, BW, 4.55)
bullets(s, ["*35 routed builds at 160 MHz:* single cascade fewest LUTs, tree the most"], y=6.05)

s = slide("Backup: kernel-size sweep, power and Fmax")
picture(s, "charts/sweep_performance.png", MX, TOP, BW, 4.55)
bullets(s, ["Power: *123 mW at 2×2 to 456 mW at 17×17*; the tree has the higher Fmax from 8×8"], y=6.05)

figure_slide("Backup: why the FIFO prefills 58 features", "diagrams/output_fifo.png", [
    "Each row gives W−N+1 features in W cycles: *N−1 gaps*",
    "*(W−N)(N−1) = 58* features cover every gap of a frame",
    "Built in LUTRAM: *no BRAM*",
    "A frame-end mark re-arms it: *no reset*",
])

s = slide("Backup: FIFO memory, LUTRAM or block RAM")
fw = (BW - 0.35) * 1.55 / 2.55
picture(s, HERE / "fifo_memory_cost.png", MX, TOP, fw, BOTTOM - TOP - 0.1)
bullets(s, [
    "Chosen at *elaboration*, by cost in the Figure of Merit",
    "LUTRAM cost *grows with the image width*",
    "A block RAM costs about the same at any size",
    "3×3 kernel: *block RAM from W = 67*",
    "Our 32×32 build: *LUTRAM*, 0 BRAM",
], MX + fw + 0.35, TOP + 0.05, BW - fw - 0.35)

s = slide("Backup: SystemVerilog testbench structure")
picture(s, "diagrams/tb_structure.png", MX + 1.5, TOP, BW - 3.0, 4.0)
bullets(s, [
    "A *reference model inside the testbench* predicts every feature of every lane",
    "The *monitor compares every valid output*: 40 configurations × 11 tests",
], y=5.55)

figure_slide("Backup: Python verification software", "verif/conv_lab_architecture.png", [
    "*Four layers*, each importing only the layers below it",
    "The *golden model* is NumPy",
    "A *file contract* connects Python to QuestaSim: stimulus in, features out",
    "The harness compares *bit for bit* and saves an image of every case",
    "*62 cases, 87 frames, 0 mismatches*",
], ratio=1.2)

s = slide("Backup: verification in detail")
table(s, [["Suite", "Result"],
          ["`conv_system_tb`: 40 configurations × 11 tests", "pass"],
          ["Block testbenches: line buffer, FIFO, kernel register", "pass"],
          ["Board wrapper `conv_axi_lite_tb` in xsim", "pass"],
          ["Python unit tests", "100 / 100"],
          ["Hardware regression: 62 cases, 87 frames", "307 328 features"],
          ["Mismatching features", "0"]], MX, TOP + 0.05, BW, [4.5, 1.4], bold_last=True)

# ------------------------------------------------------------------ backup: test images
CAP = "Rows: Sobel-X, Sobel-Y, Laplacian · columns: input, hardware, golden model · *all match*"
for title, left, right in (("Backup: test images, circle and checkerboard", "cli_circle_128", "cli_checker_128"),
                           ("Backup: test images, bars and edges", "cli_bars_128", "cli_edges_128")):
    s = slide(title)
    picture(s, "verif/%s.png" % left, MX + 1.4, TOP, 4.4, 4.85)
    picture(s, "verif/%s.png" % right, W - MX - 1.4 - 4.4, TOP, 4.4, 4.85)
    text(s, CAP, MX, 6.3, BW, 0.4, 18, align=PP_ALIGN.CENTER)

s = slide("Backup: twelve kernels on one frame")
picture(s, "verif/cli_edges_12_128_a.png", MX, TOP, 2.55, BOTTOM - TOP)
picture(s, "verif/cli_edges_12_128_b.png", MX + 2.8, TOP, 2.55, BOTTOM - TOP)
bullets(s, [
    "All *12 preset kernels* as parallel lanes of *one* 128×128 frame",
    "Columns: input, hardware, golden model",
    "Gradients, Laplacians, blurs, sharpen and emboss on the same edges",
    "*190 512 features*, all bit-exact",
], MX + 5.75, TOP + 0.05, BW - 5.75)

s = slide("Backup: five kernels, and ReLU")
picture(s, "verif/cli_circle.png", MX, TOP, 2.95, BOTTOM - TOP)
picture(s, "verif/cli_checker_relu.png", MX + 3.3, TOP, 4.3, 3.25, valign="top")
bullets(s, [
    "Left: 32×32 circle through *five kernels* in parallel",
    "Above: checkerboard with *ReLU* on the output",
    "Every lane: *MATCH*",
], MX + 3.3, TOP + 3.45, BW - 3.3)

s = slide("Backup: regression test images")
x = MX
for name, wd in (("regression_presets", 3.7), ("regression_taps", 1.67), ("regression_ties", 2.45)):
    picture(s, "verif/%s.png" % name, x, TOP, wd, BOTTOM - TOP)
    x += wd + 0.22
bullets(s, [
    "*Presets:* every preset kernel on the checkerboard",
    "*Taps:* one weight at a time, to prove the tap order",
    "*Ties:* values exactly on a rounding tie",
    "*62 cases, 87 frames, 0 mismatches*",
], x + 0.1, TOP + 0.05, W - MX - x - 0.1)

out = HERE / "slides.pptx"
prs.save(out)
print(f"wrote {out} ({page_no[0]} slides)")
