// =====================================================================
//  ARA Silicon - short presentation, IEEE SSCS Egypt 2026 Student Design Competition
//  Build (from docs/presentation):  typst compile --root .. slides.typ slides.pdf
//  Numbers come from ../report/results.typ, figures from ../report/figures.
// =====================================================================
#import "../report/results.typ": *

#let navy  = rgb("#1F3A5F")
#let blue  = rgb("#2B5A8F")
#let red   = rgb("#B85450")
#let green = rgb("#2E7D32")
#let muted = rgb("#5F6368")
#let tint  = rgb("#F1F5FA")
#let fig-dir = "../report/figures/"

#set document(title: "ARA Silicon - Edge-AI CNN Convolution Accelerator", author: "ARA Silicon")
#set page(paper: "presentation-16-9", margin: (x: 1.4cm, top: 2.9cm, bottom: 1.1cm), header-ascent: 25%)
#set text(font: ("Segoe UI", "Calibri", "Arial"), size: 17pt, fill: rgb("#1A1A1A"))
#set par(justify: false, leading: 0.55em)
#set list(marker: text(fill: blue)[▸], spacing: 0.7em)
#show raw: set text(font: ("Cascadia Mono", "Consolas"), size: 0.9em)
#show strong: set text(fill: navy)

#let slide(title, body) = page(
  header: align(bottom, block(width: 100%)[
    #text(size: 25pt, weight: "bold", fill: navy, title)
    #v(-0.35em)
    #line(length: 100%, stroke: 1.6pt + blue)
  ]),
  footer: context text(size: 10pt, fill: muted)[
    ARA Silicon · Edge-AI CNN Convolution Accelerator #h(1fr) #counter(page).get().first()
  ],
  body,
)

#let img(path, ..args) = image(fig-dir + path, ..args)

#let card(value, label, accent: navy) = box(
  width: 100%, fill: tint, radius: 6pt, inset: (x: 8pt, y: 10pt), stroke: (left: 4pt + accent),
  align(center)[
    #text(size: 26pt, weight: "bold", fill: accent, value) \
    #v(-0.3em)
    #text(size: 12pt, fill: muted, label)
  ],
)

#let note(body) = block(fill: tint, radius: 5pt, inset: 10pt, width: 100%, text(size: 15pt, body))

#let small-table(..args) = {
  set text(size: 13.5pt)
  table(
    stroke: (x, y) => (bottom: if y == 0 { 1pt + navy } else { 0.4pt + rgb("#D5DFEC") }),
    fill: (x, y) => if y == 0 { navy } else if calc.even(y) { tint },
    inset: (x: 7pt, y: 5pt),
    ..args,
  )
}
#let th(body) = text(fill: white, weight: "bold", body)

// ---------------------------------------------------------------------
//  1. Title
// ---------------------------------------------------------------------
#page(margin: 0pt, header: none, footer: none)[
  #block(width: 100%, height: 62%, fill: navy, inset: (x: 1.6cm, y: 1.4cm))[
    #text(size: 13pt, fill: rgb("#C9D6E8"))[IEEE SSCS Egypt Chapter · 2026 Student Design Competition]
    #v(1fr)
    #text(size: 34pt, weight: "bold", fill: white)[FPGA-Based Edge-AI Vision Accelerator \ for N×N CNN Convolution]
    #v(0.2em)
    #text(size: 18pt, fill: rgb("#DCE6F2"))[Architecture, Verification and FPGA Implementation]
  ]
  #block(inset: (x: 1.6cm, y: 0.9cm))[
    #text(size: 22pt, weight: "bold", fill: navy)[ARA Silicon] #h(0.6em) #text(size: 16pt, fill: muted)[Ain Shams University]
    #v(0.3em)
    #text(size: 15pt)[Ahmed Ashraf #h(1.2em) · #h(1.2em) Rana Ayman #h(1.2em) · #h(1.2em) Ammar Ahmed]
    #v(0.6em)
    #text(size: 13pt, fill: muted)[AMD Zynq-7020 (PYNQ-Z2) · SystemVerilog · QuestaSim · Vivado 2018.2 · Python golden model]
  ]
]

// ---------------------------------------------------------------------
//  2. Task and metric
// ---------------------------------------------------------------------
#slide[The task and the metric][
  #grid(columns: (1.1fr, 1fr), column-gutter: 1.2cm,
    [
      - Streaming N×N convolution of a grayscale image, stride 1, valid padding
      - 8-bit unsigned pixels, 8-bit signed programmable kernels
      - 16-bit signed output features; competition point 3×3 on 32×32
      - Bonuses: ReLU, one output pixel per cycle, multiple kernels, board demo, edge detection
    ],
    [
      #note[
        #align(center)[
          #text(size: 15pt)[$ "FoM" = "Throughput" / ("Power" times ("LUT" + 50 · "DSP" + 100 · "BRAM")) $]
        ]
      ]
      #v(0.6em)
      *Design principle* \
      Flip-flops are free in the FoM, one DSP costs 50 LUTs, one BRAM 100: move every
      addition into DSP slices, store in shift registers and flip-flops, avoid BRAM.
    ],
  )
]

// ---------------------------------------------------------------------
//  3. Results at a glance
// ---------------------------------------------------------------------
#slide[Results at a glance (3×3, 32×32, 250 MHz, routed)][
  #grid(columns: (1fr,) * 4, column-gutter: 0.5cm, row-gutter: 0.5cm,
    card([#fpga.luts], [LUTs (0.15 %)]),
    card([#fpga.dsps], [DSP48E1 · 0 BRAM]),
    card([#weighted-area], [LUT + 50 DSP + 100 BRAM]),
    card([#perf.fmax], [Fmax (MHz) · WNS +#perf.wns ns]),
    card([#fix(perf.power-total-checker * 1000, digits: 1)], [mW, checker + Sobel-Y], accent: blue),
    card([#fix(fom-checker, digits: 5)], [FoM, checker + Sobel-Y], accent: green),
    card([#fix(fom, digits: 5)], [FoM, bars + Sobel-X], accent: green),
    card([1 px / cycle], [sustained throughput], accent: red),
  )
  #v(0.7em)
  #grid(columns: (1fr, 1fr), column-gutter: 1cm,
    [- Frames stream back to back *without reset* (`o_frame_done`)
     - *All five bonus features* implemented],
    [- *0 mismatches* in #verif.cases regression features
     - Generic in kernel size, image size and kernel count],
  )
]

// ---------------------------------------------------------------------
//  4. Architecture
// ---------------------------------------------------------------------
#slide[Streaming architecture][
  #align(center, img("diagrams/arch_blocks.png", width: 96%))
  #v(0.4em)
  #grid(columns: (1fr, 1fr, 1fr), column-gutter: 0.8cm,
    [*Shared front end* \ input registers, (N−1)-row line buffer, N×N window],
    [*Per-kernel lane* \ kernel register, MAC, round half up, optional ReLU, FIFO],
    [*Valid-driven pipeline* \ no FSM register; stalls freeze every stage],
  )
]

// ---------------------------------------------------------------------
//  5. Line buffer and window
// ---------------------------------------------------------------------
#slide[Line buffer and sliding window][
  #grid(columns: (1.35fr, 1fr), column-gutter: 0.8cm,
    align(horizon, img("diagrams/line_buffer_window.png", width: 100%)),
    [
      - N−1 rows in *shift-register LUTs* (SRLC32E): 512 bits in 16 SRLs
      - Live row never stored; each write moves the window one column
      - Frame position as a *one-hot ring* of W flip-flops: no counter LUTs
      - Whole line buffer: *22 LUTs*, no BRAM
      #note[A LUTRAM ring saved 8 LUTs but cost 1–2 mW: FoM unchanged, SRL kept.]
    ],
  )
]

// ---------------------------------------------------------------------
//  6. DSP cascade
// ---------------------------------------------------------------------
#slide[MAC: all arithmetic inside DSP48E1 slices][
  #grid(columns: (1.5fr, 1fr), column-gutter: 0.8cm,
    align(horizon, img("diagrams/mac_single_chain.png", width: 100%)),
    [
      - Slice e: $"acc"_e = "acc"_(e-1) + p_e dot w_e$ in the post-adder
      - Partial sum on the dedicated *PCOUT → PCIN* path
      - AREG / BREG / MREG / PREG all used
      - Tap e waits e+1 cycles: *skew flip-flops*, free in the FoM
      #note[
        MAC = *2 LUTs* (was 143 with a fabric adder tree) \
        latency 2 + N² = 11 cycles
      ]
    ],
  )
]

// ---------------------------------------------------------------------
//  7. Three architectures and selection
// ---------------------------------------------------------------------
#slide[Three MAC architectures, one selected per build][
  #grid(columns: (1fr, 1.25fr), column-gutter: 0.8cm,
    align(horizon, img("diagrams/mac_selection.png", height: 88%)),
    [
      #small-table(
        columns: (auto, 1fr, 1fr, 1fr),
        th[], th[Single cascade], th[Row chains], th[Tree],
        [Additions], [DSP only], [DSP + ⌈log₂N⌉ tree], [fabric tree],
        [Skew FFs], [∝ N⁴], [∝ N³], [none],
        [Limit], [one 60-DSP column], [220 DSPs], [LUT multipliers],
        [3×3 LUT / FF], [*70 / 474*], [110 / 322], [205 / 429],
        [3×3 FoM], [*0.01731*], [0.01612], [0.01227],
      )
      #v(0.4em)
      - Elaboration-time rule from N and K; `MAC_ARCH` can force one
      - All three verified bit-exact across N and K
    ],
  )
]

// ---------------------------------------------------------------------
//  8. Sweep
// ---------------------------------------------------------------------
#slide[Why three: kernel-size sweep N = 2…17 at 160 MHz][
  #grid(columns: (1.35fr, 1fr), column-gutter: 0.7cm,
    align(horizon, img("charts/sweep_fom_ratio.png", width: 100%)),
    [
      - 35 routed builds, SAIF power, one kernel
      - *Single cascade* best FoM for N ≤ 4, then its N⁴ skew and one DSP column end it at 7×7
      - *Row chains* best for N = 5–11, scale to 196 DSPs
      - *Tree* best from N = 12, highest Fmax, the only one past 220 DSPs (17×17 with LUT multipliers)
      #note[System = best architecture at 12 of 16 sizes; the limits are parameters (4 and 11 at 160 MHz).]
    ],
  )
]

// ---------------------------------------------------------------------
//  9. Rounding and saturation
// ---------------------------------------------------------------------
#slide[Output stage: round half up, no saturation][
  #grid(columns: (1fr, 1fr), column-gutter: 0.8cm,
    [
      #small-table(
        columns: (1.6fr, auto, auto, auto),
        th[Variant (full accelerator)], th[LUT], th[Fmax], th[FoM],
        [*Round half up, clamp if reachable*], [*78*], [*305.6*], [*0.01712*],
        [Round half to even], [93], [278.9], [0.01658],
        [Half up, clamp always built], [99], [287.4], [0.01527],
      )
      #v(0.3em)
      - Same RMS error as half-to-even (0.29 LSB), bias only 1/32 LSB
      - One guard-bit incrementer instead of guard + sticky + LSB logic
      - DROP = ⌈log₂N²⌉ keeps |y| ≤ 32 640 for every N: *overflow is impossible*
      - Clamp generated automatically if widths change
    ],
    align(horizon, img("charts/saturation_headroom.png", width: 100%)),
  )
]

// ---------------------------------------------------------------------
//  10. One pixel per cycle and frames without reset
// ---------------------------------------------------------------------
#slide[One pixel per cycle, frames without reset][
  #align(center, img("waves/xsim_power_rowedge.png", width: 72%))
  #set text(size: 15pt)
  #grid(columns: (1fr, 1fr), column-gutter: 1cm,
    [- The window is invalid for N−1 pixels at each row edge
     - A prefill FIFO of (W−N)(N−1) = 58 features hides the gaps: `o_valid` stays high],
    [- `o_frame_done` on the last feature of every frame
     - Frame-end mark as a flip-flop delay line; registered FIFO clear re-arms for the next frame (+7 LUTs)],
  )
]

// ---------------------------------------------------------------------
//  11. Verification
// ---------------------------------------------------------------------
#slide[Verification: two independent references][
  #align(center, img("diagrams/verification_flow.png", width: 92%))
  #v(0.2em)
  #grid(columns: (1fr,) * 4, column-gutter: 0.4cm,
    card([40 × 11], [SV configs × tests]),
    card([100], [Python unit tests]),
    card([62 / 87], [regression cases / frames]),
    card([0], [mismatching features], accent: green),
  )
]

// ---------------------------------------------------------------------
//  12. Hardware vs golden model
// ---------------------------------------------------------------------
#slide[RTL versus golden model, bit for bit][
  #grid(columns: (1fr, 1fr), column-gutter: 0.6cm,
    align(center + horizon, img("verif/cli_inspection.png", height: 80%)),
    [
      #align(center, img("verif/cli_edges_128.png", height: 48%))
      #set text(size: 15pt)
      - 128×128 images, 3 kernels as parallel lanes: 47 628 features each
      - All 12 presets in one frame, 1–16 lanes, 2×2 to 11×11 windows
      - Input | hardware (QuestaSim) | Python reference
    ],
  )
]

// ---------------------------------------------------------------------
//  13. FPGA implementation
// ---------------------------------------------------------------------
#slide[FPGA implementation on the xc7z020][
  #grid(columns: (1.05fr, 1fr), column-gutter: 0.7cm,
    [
      #img("vivado/device_view.png", width: 100%)
      #text(size: 12pt, fill: muted)[red MAC · blue line buffer · green window · magenta FIFO · yellow kernel · cyan round]
    ],
    [
      #img("vivado/power.PNG", width: 100%)
      #v(0.3em)
      - 250 MHz met: WNS +0.728 ns, WHS +0.082 ns
      - Critical path in FIFO control, not arithmetic
      - 94 % of power is device static (idle Zynq PS)
    ],
  )
]

// ---------------------------------------------------------------------
//  14. Board demo
// ---------------------------------------------------------------------
#slide[Board demonstration on the PYNQ-Z2][
  #grid(columns: (1.5fr, 1fr), column-gutter: 0.7cm,
    align(horizon, img("diagrams/board_demo.png", width: 100%)),
    [
      - `conv_axi_lite` wrapper at `0x43C00000`: kernels, pixel bursts, result BRAM, status, LEDs
      - Python driver + golden model in a Jupyter notebook; every frame compared
      - Overlay: 813 LUT, WNS +2.56 ns at 100 MHz
      - Simulated in xsim before the board: 3 builds × 6 frames, 0 mismatches
    ],
  )
]

// ---------------------------------------------------------------------
//  15. Conclusion
// ---------------------------------------------------------------------
#slide[Conclusion][
  #v(0.4em)
  - *All arithmetic in DSP48E1 slices:* a 3×3 window sum with 2 LUTs
  - Complete accelerator: *#fpga.luts LUTs, 9 DSPs, 0 BRAM* at *#perf.fmax MHz*, one pixel per cycle
  - FoM *#fix(fom-checker, digits: 5)* (checker + Sobel-Y) and *#fix(fom, digits: 5)* (bars + Sobel-X)
  - One generic RTL chooses among three MAC architectures from N and K, justified by a 35-build sweep
  - Round half up without saturation: provably exact range, 3 LUTs
  - Continuous streaming, all bonuses, verified bit-exact and demonstrated on the PYNQ-Z2
  #v(1fr)
  #align(center, text(size: 30pt, weight: "bold", fill: navy)[Thank you — questions?])
  #v(0.6em)
]
