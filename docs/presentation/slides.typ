// =====================================================================
//  ARA Silicon - final-round presentation
//  IEEE SSCS Egypt Chapter, 2026 Student Design Competition, 21 November 2026
//  15 min talk (slides 2-19) + backup slides for the question round.
//  Build (from docs/presentation):  typst compile --root .. slides.typ slides.pdf
//  Numbers come from ../report/results.typ, figures from ../report/figures.
//  Colours and logos follow the IEEE SSCS Egypt Chapter announcement.
// =====================================================================
#import "../report/results.typ": *

#let crimson = rgb("#B90B2E")   // IEEE SSCS
#let ieee    = rgb("#006699")   // IEEE blue
#let ink     = rgb("#1A1A1A")
#let muted   = rgb("#55595E")
#let tint    = rgb("#F3F6F9")
#let fig-dir = "../report/figures/"

#set document(title: "ARA Silicon - Edge-AI CNN Convolution Accelerator", author: "ARA Silicon")
#set page(paper: "presentation-16-9", margin: (x: 1.5cm, top: 3.1cm, bottom: 1.2cm), header-ascent: 22%)
#set text(font: ("Segoe UI", "Calibri", "Arial"), size: 21pt, fill: ink)
#set par(justify: false, leading: 0.58em)
#set list(marker: text(fill: crimson, size: 0.9em)[●], spacing: 0.95em, indent: 0.1em, body-indent: 0.55em)
#show raw: set text(font: ("Cascadia Mono", "Consolas"), size: 0.92em)
#show strong: set text(fill: ieee)

#let slide(title, body) = page(
  header: block(width: 100%)[
    #grid(columns: (1fr, auto), align: (left + bottom, right + bottom),
      text(size: 29pt, weight: "bold", fill: ieee, title),
      image("logo_sscs_egypt.png", height: 1.25cm),
    )
    #v(-0.5em)
    #line(length: 100%, stroke: 2.2pt + crimson)
  ],
  footer: context text(size: 12pt, fill: muted)[
    ARA Silicon · Ain Shams University #h(1fr) IEEE SSCS Egypt · 2026 Student Design Competition #h(1fr) #counter(page).get().first()
  ],
  body,
)

#let img(path, ..args) = image(fig-dir + path, ..args)

// One big number with a readable label.
#let card(value, label, accent: ieee) = box(
  width: 100%, fill: tint, radius: 6pt, inset: (x: 8pt, y: 13pt), stroke: (top: 4pt + accent),
  align(center)[
    #text(size: 33pt, weight: "bold", fill: accent, value) \
    #v(-0.25em)
    #text(size: 16pt, fill: ink, label)
  ],
)

// Reference tables (backup slides only).
#let ref-table(..args) = {
  set text(size: 16.5pt)
  table(
    stroke: (x, y) => (bottom: if y == 0 { 1.2pt + ieee } else { 0.5pt + rgb("#D3DCE4") }),
    fill: (x, y) => if y == 0 { ieee } else if calc.even(y) { tint },
    inset: (x: 9pt, y: 7pt),
    ..args,
  )
}
#let th(body) = text(fill: white, weight: "bold", body)

// ---------------------------------------------------------------------
//  1. Title
// ---------------------------------------------------------------------
#page(margin: 0pt, header: none, footer: none)[
  #set block(spacing: 0pt)
  #block(width: 100%, height: 19%, inset: (x: 1.6cm, y: 0.7cm))[
    #grid(columns: (1fr, auto), align: (left + horizon, right + horizon),
      image("logo_sscs_egypt.png", height: 2.3cm),
      image("logo_ieee_egypt.png", height: 1.7cm),
    )
  ]
  #block(width: 100%, height: 47%, fill: crimson, inset: (x: 1.6cm, y: 1.1cm))[
    #text(size: 17pt, fill: rgb("#F6D9DF"))[2026 Student Design Competition]
    #v(1fr)
    #text(size: 38pt, weight: "bold", fill: white)[FPGA-Based Edge-AI Vision Accelerator \ for N×N CNN Convolution]
    #v(0.25em)
    #text(size: 21pt, fill: rgb("#F6D9DF"))[Architecture · Verification · FPGA Implementation]
  ]
  #block(inset: (x: 1.6cm, y: 0.8cm))[
    #text(size: 27pt, weight: "bold", fill: ieee)[ARA Silicon] #h(0.6em) #text(size: 20pt, fill: muted)[Ain Shams University]
    #v(0.35em)
    #text(size: 21pt)[Ahmed Ashraf #h(1em) · #h(1em) Rana Ayman #h(1em) · #h(1em) Ammar Ahmed]
  ]
]

// ---------------------------------------------------------------------
//  2. Design principle
// ---------------------------------------------------------------------
#slide[Design principle: follow the Figure of Merit][
  - In the Figure of Merit, flip-flops are *free*, one DSP costs 50 LUTs, one BRAM costs 100
  - *Our principle:* do every addition *inside the DSP slices*, and make the *most efficient use of memory*
  - *One generic RTL:* any kernel size (2×2 to 17×17), image size and number of kernels; ReLU optional
  - *MAC architecture selected automatically* from the kernel size and the number of kernels
  - *FIFO memory selected automatically:* LUTRAM or BRAM, whichever costs less in the FoM — our build needs only LUTRAM
]

// ---------------------------------------------------------------------
//  3. Results at a glance
// ---------------------------------------------------------------------
#slide[Results at a glance][
  #text(size: 21pt)[*Build:* #design.kernel-n×#design.kernel-n kernel · #design.image-w×#design.image-h image · one kernel · 8-bit data · 16-bit output]
  #v(-0.2em)
  #grid(columns: (1fr,) * 3, column-gutter: 0.6cm, row-gutter: 0.4cm,
    card([#fpga.luts LUTs], [0.15 % of the device], accent: crimson),
    card([#fpga.dsps DSPs], [0 BRAM · all arithmetic in DSPs]),
    card([#perf.fmax MHz], [Fmax · 250 MHz timing met]),
    card([#fix(perf.power-total-checker * 1000, digits: 1) mW], [total power, routed SAIF]),
    card([1 px / cycle], [sustained throughput]),
    card([#fix(fom-checker, digits: 5)], [Figure of Merit], accent: crimson),
  )
  #v(0.3em)
  - *0 mismatches* against the golden model in #verif.cases output features
  - *All five bonus features*; frames stream *without a reset*, with *input stall support*
]

// ---------------------------------------------------------------------
//  4. Architecture                                   (committee point 1)
// ---------------------------------------------------------------------
#slide[Architecture: one streaming pipeline][
  #align(center, img("diagrams/arch_blocks.png", width: 92%))
  #v(0.3em)
  - *Shared front end:* input registers, line buffer, N×N window
  - *One lane per kernel:* weights, MAC, rounding, ReLU, output FIFO
]

// ---------------------------------------------------------------------
//  5. Datapath and fixed-point widths                (committee point 2)
// ---------------------------------------------------------------------
#slide[Datapath: bit widths, overflow, saturation][
  - 8-bit pixel × 8-bit weight = *16-bit product*
  - Sum of N² products: the accumulator grows by ⌈log₂N²⌉ bits → *#derived.acc-bits bits, exact*
  - Drop the same ⌈log₂N²⌉ bits and *round half up* → 16-bit output
  - Largest result is 255 × 128 = *32 640*, below 32 768 for *every N*: *overflow cannot happen*
  - The saturation clamp is generated only if a width change makes it reachable
  #v(0.2em)
  #align(center, img("diagrams/round_saturate.png", width: 62%))
]

// ---------------------------------------------------------------------
//  6. Line buffer and window                         (committee point 2)
// ---------------------------------------------------------------------
#slide[Line buffer and sliding window][
  #align(center, img("diagrams/line_buffer_window.png", width: 88%))
  #v(0.1em)
  #grid(columns: (1fr, 1fr), column-gutter: 1cm,
    [
      - N−1 rows in *shift-register LUTs*
      - The live row is *never stored*
    ],
    [
      - Row position: a *one-hot ring*
      - Whole line buffer: *22 LUTs, 0 BRAM*
    ],
  )
]

// ---------------------------------------------------------------------
//  7. Control                                        (committee point 2)
// ---------------------------------------------------------------------
#slide[Control: an implicit FSM][
  #grid(columns: (1.35fr, 1fr), column-gutter: 0.9cm,
    align(horizon, img("diagrams/control_fsm.png", width: 100%)),
    [
      - *No FSM state register*: a *valid bit* travels with the data
      - States are decoded from *counters the datapath already has*
      - *Stall:* when `i_pixel_valid` drops, the front end *holds*; the MAC finishes what is inside and the FIFO covers the gap
      - After `o_frame_done`: next frame, *no reset*
    ],
  )
]

// ---------------------------------------------------------------------
//  8. DSP cascade
// ---------------------------------------------------------------------
#slide[One DSP48E1 slice][
  #grid(columns: (1.4fr, 1fr), column-gutter: 0.9cm,
    align(horizon, img("diagrams/dsp48e1_slice.png", width: 100%)),
    [
      - P = PCIN + A × B: the *post-adder accumulates*
      - AREG, BREG, MREG, PREG *all enabled*
      - Tap e is delayed e+1 cycles by *skew flip-flops*
      - Flip-flops are free in the FoM
    ],
  )
]

#slide[MAC 1: multiplier array + adder tree][
  #grid(columns: (1.3fr, 1fr), column-gutter: 0.9cm,
    align(horizon, img("diagrams/mac_tree.png", width: 100%)),
    [
      - *N² parallel DSP multipliers*
      - A *pipelined binary adder tree* in fabric
      - Simple, but the tree costs LUTs: *143 at 3×3*
      - The only one that continues *past 220 DSPs*, with LUT multipliers
      - Used for *large kernels*, up to 17×17
    ],
  )
]

#slide[MAC 2: row DSP chains][
  #grid(columns: (1.4fr, 1fr), column-gutter: 0.9cm,
    align(horizon, img("diagrams/mac_row_chain.png", width: 100%)),
    [
      - *One DSP chain per window row*
      - Row additions move *inside the DSPs*; only a small tree remains
      - 3×3 MAC: *43 LUTs*
      - Scales to *196 DSPs* (14×14)
      - Used for *N = 4 to 8*, and for several kernels
    ],
  )
]

#slide[MAC 3: single DSP cascade][
  #grid(columns: (1.4fr, 1fr), column-gutter: 0.9cm,
    align(horizon, img("diagrams/mac_single_chain.png", width: 100%)),
    [
      - All N² slices in *one PCOUT → PCIN chain*
      - *Every addition is inside a DSP*: the 3×3 MAC is *2 LUTs*
      - Cost: delay flip-flops grow as N⁴ — *free in the FoM*
      - Used for *N ≤ 3*, one kernel: *the competition build*
    ],
  )
]

// ---------------------------------------------------------------------
//  9. Three architectures and selection
// ---------------------------------------------------------------------
#slide[One of the three is selected automatically][
  #grid(columns: (1.15fr, 1fr), column-gutter: 0.9cm,
    align(center + horizon, img("diagrams/mac_selection.png", width: 100%)),
    [
      - Decided at *elaboration* from the kernel size N and kernel count K
      - Only the *selected* architecture is built
      - `MAC_ARCH` can force any one
      - The limits are *parameters*
      - All three verified *bit-exact*
    ],
  )
]

// ---------------------------------------------------------------------
//  10. Sweep
// ---------------------------------------------------------------------
#slide[Why three: kernel sizes 2×2 to 17×17][
  #grid(columns: (1.35fr, 1fr), column-gutter: 0.9cm,
    align(horizon, img("charts/sweep_fom_ratio.png", width: 100%)),
    [
      - *35 routed builds* at 160 MHz
      - Single cascade wins for *N ≤ 4*
      - Row chains win for *N = 5 to 11*
      - The tree wins from *N = 12* and is the only one that reaches 17×17
    ],
  )
]

// ---------------------------------------------------------------------
//  11. Rounding and saturation                       (committee point 2)
// ---------------------------------------------------------------------
#slide[Rounding: half up, and no saturation logic][
  #grid(columns: (1fr, 1fr), column-gutter: 0.9cm,
    [
      - *Round half up:* 78 LUTs, 305.6 MHz
      - Round half to even: 93 LUTs, 278.9 MHz
      - *Same RMS error*, 0.29 LSB; bias only 1/32 LSB
      - Always building the clamp: 99 LUTs, FoM −11 %
      - We keep the *smallest stage that is still exact*
    ],
    align(horizon, img("charts/saturation_headroom.png", width: 100%)),
  )
]

// ---------------------------------------------------------------------
//  12. One pixel per cycle and frames without reset
// ---------------------------------------------------------------------
#slide[One pixel per cycle, frames without reset][
  #align(center, img("waves/xsim_power_rowedge.png", width: 74%))
  #v(0.2em)
  - The window is invalid for N−1 pixels at each row edge
  - A *prefill FIFO of 58 features* hides the gaps: `o_valid` never drops
  - `o_frame_done` marks the last feature; the next frame needs *no reset*
]

// ---------------------------------------------------------------------
//  Full architecture                                 (committee point 1)
// ---------------------------------------------------------------------
#slide[Full architecture: the datapath in detail][
  #align(center + horizon, img("diagrams/arch_detailed.png", width: 100%))
]

// ---------------------------------------------------------------------
//  13. Verification                                  (committee point 3)
// ---------------------------------------------------------------------
#slide[Verification: two independent references][
  #align(center, img("diagrams/verification_flow.png", width: 84%))
  #v(0.2em)
  #grid(columns: (1fr,) * 4, column-gutter: 0.5cm,
    card([40 × 11], [SV configs × tests]),
    card([100], [Python unit tests]),
    card([87], [regression frames]),
    card([0], [mismatches], accent: crimson),
  )
]

// ---------------------------------------------------------------------
//  14. Hardware vs golden model                      (committee point 3)
// ---------------------------------------------------------------------
#slide[Hardware versus golden model: bit for bit][
  #grid(columns: (1.15fr, 1fr), column-gutter: 0.9cm,
    align(center + horizon, img("verif/cli_inspection.png", height: 92%)),
    [
      - Golden model in *Python / NumPy*
      - 128×128 images, *3 kernels in parallel*
      - *47 628 features* per image, every one identical
      - Kernel sizes 2×2 to 11×11, 1 to 16 kernels
      - *#verif.cases features compared, 0 mismatches*
    ],
  )
]

// ---------------------------------------------------------------------
//  Figure of Merit                                   (committee point 4)
// ---------------------------------------------------------------------
#slide[Figure of Merit][
  #align(center, text(size: 27pt)[
    $ "FoM" = "Throughput" / ("Power" times ("LUT" + 50 dot "DSP" + 100 dot "BRAM")) $
  ])
  #v(0.5em)
  - *Throughput:* 1 pixel per clock cycle, sustained
  - *Area:* #fpga.luts LUT + 50 × #fpga.dsps DSP + 100 × #fpga.brams BRAM = *#weighted-area*
  - *Power:* #fix(perf.power-total-checker * 1000, digits: 1) mW, from a routed SAIF (checkerboard + Sobel-Y)
  - *FoM* = 1 / (#fix(perf.power-total-checker, digits: 4) W × #weighted-area) = *#fix(fom-checker, digits: 5)*
  - Second workload, bars + Sobel-X: #fix(perf.power-total * 1000, digits: 1) mW, FoM *#fix(fom, digits: 5)*
]

// ---------------------------------------------------------------------
//  15. FPGA implementation                           (committee point 4)
// ---------------------------------------------------------------------
#slide[FPGA results on the Zynq-7020][
  #grid(columns: (1fr, 1.2fr), column-gutter: 0.9cm,
    align(horizon, img("vivado/device_view.png", width: 100%)),
    [
      - *Utilization:* #fpga.luts LUT · #fpga.ffs FF · #fpga.dsps DSP · 0 BRAM
      - *Timing:* 250 MHz met, WNS +#perf.wns ns
      - *Fmax:* #perf.fmax MHz
      - *Power:* #fix(perf.power-total-checker * 1000, digits: 1) mW, of which #fix(perf.power-dynamic-checker * 1000, digits: 1) mW dynamic
      - *Latency:* #design.pipeline-stages cycles per pixel
      - *Throughput:* 1 pixel per cycle = 250 Mpx/s
      - *FoM:* #fix(fom-checker, digits: 5)
    ],
  )
]

// ---------------------------------------------------------------------
//  16. Bonus features                                (committee point 5)
// ---------------------------------------------------------------------
#slide[All five bonus features][
  - *ReLU activation* — per kernel, parameter `ENABLE_RELU`
  - *One output pixel per cycle* — 900 features in 900 consecutive cycles
  - *Multiple kernels* — 1 to 16 in parallel, sharing one window
  - *Board demonstration* — PYNQ-Z2 overlay with a Python driver
  - *Edge-detection demo* — Sobel and Laplacian on 128×128 images
  #v(0.5em)
  - Beyond the brief: *frames back to back without a reset*, and one RTL for every kernel size from 2×2 to 17×17
]

// ---------------------------------------------------------------------
//  18. Trade-offs and improvements                   (committee point 6)
// ---------------------------------------------------------------------
#slide[Trade-offs, and what we would improve][
  #grid(columns: (1fr, 1fr), column-gutter: 1.1cm,
    [
      #text(size: 24pt, weight: "bold", fill: crimson)[Trade-offs we made]
      #v(0.2em)
      - *Flip-flops instead of LUTs:* +7 % FoM
      - *No saturation logic:* proven unreachable
      - *Shift registers, not BRAM,* for the line buffer
      - *Reported at 250 MHz:* lower FoM than 150 MHz, but best energy per pixel
    ],
    [
      #text(size: 24pt, weight: "bold", fill: crimson)[What we would improve]
      #v(0.2em)
      - *Tune the architecture limits* for each target clock
      - *AXI-Stream / DMA* on the board instead of register writes
      - *Multi-channel and multi-layer* convolution
      - *Formal verification* of each block
    ],
  )
]

// ---------------------------------------------------------------------
//  19. Conclusion
// ---------------------------------------------------------------------
#slide[Conclusion][
  - *All arithmetic in DSP slices:* a 3×3 MAC in 2 LUTs
  - *#fpga.luts LUTs, #fpga.dsps DSPs, 0 BRAM* at *#perf.fmax MHz*, one pixel per cycle
  - *FoM #fix(fom-checker, digits: 5)* from routed, SAIF-based power
  - *One generic RTL,* three MAC architectures, 2×2 to 17×17
  - *Bit-exact* against the golden model, all five bonuses
  #v(1fr)
  #align(center, text(size: 36pt, weight: "bold", fill: crimson)[Thank you — questions?])
  #v(0.4em)
]

// =====================================================================
//  Backup slides for the question round (not part of the 15 minutes)
// =====================================================================
#page(margin: 0pt, header: none, footer: none)[
  #block(width: 100%, height: 100%, fill: ieee, inset: 1.6cm)[
    #align(center + horizon)[
      #text(size: 44pt, weight: "bold", fill: white)[Backup slides]
    ]
  ]
]


#slide[Backup: board demonstration on the PYNQ-Z2][
  #grid(columns: (1.4fr, 1fr), column-gutter: 0.9cm,
    align(horizon, img("diagrams/board_demo.png", width: 100%)),
    [
      - *AXI4-Lite wrapper* around the accelerator
      - *Python driver* and golden model in a Jupyter notebook
      - *Every frame is compared* against the reference
      - Simulated end to end first: *0 mismatches*
    ],
  )
]

#slide[Backup: latency of one pixel][
  #grid(columns: (1.1fr, 1fr), column-gutter: 0.9cm,
    ref-table(
      columns: (1.6fr, auto),
      th[Stage], th[Cycles],
      [Input registers], [1],
      [Line buffer], [0],
      [Window generator], [1],
      [MAC, single cascade (2 + N²)], [11],
      [Round and saturate], [2],
      [ReLU (when enabled: 1)], [0],
      [Output FIFO], [1],
      [*Pipeline depth*], [*#design.pipeline-stages*],
    ),
    [
      - First feature after *#perf.latency cycles* (line fill + FIFO prefill)
      - Whole 32×32 frame in *#perf.frame-cycles cycles*
      - Then *one feature every cycle*
    ],
  )
]

#slide[Backup: alternatives we built and rejected][
  #ref-table(
    columns: (2.2fr, auto, auto, auto, auto),
    th[Approach], th[LUT], th[FF], th[DSP], th[FoM],
    [Baseline: multipliers + fabric adder tree], [243], [442], [9], [0.01061],
    [DSP row chains], [149], [335], [9], [0.01284],
    [*Single 9-DSP cascade (chosen)*], [*68*], [*456*], [*9*], [*0.01520*],
    [Double MAC, two products per DSP], [429], [919], [5], [0.01023],
    [DSP multi-pumping × 3], [262], [380], [3], [0.00503],
    [Fabric multipliers, no DSP], [933], [—], [0], [fails timing],
  )
  #v(0.4em)
  - Every candidate was *verified first*, then measured on the same flow
]

#slide[Backup: where the LUTs go][
  #grid(columns: (1.1fr, 1fr), column-gutter: 0.9cm,
    ref-table(
      columns: (1.7fr, auto, auto),
      th[Module], th[LUT], th[FF],
      [`line_buffer`], [22], [39],
      [`window_generator`], [3], [75],
      [`kernel_register`], [5], [76],
      [`mac_single_chain`], [2], [226],
      [`round_saturate`], [3], [35],
      [`output_fifo`], [43], [32],
      [`conv_system` top], [0], [38],
      [*Total*], [*#fpga.luts*], [*#fpga.ffs*],
    ),
    [
      - The MAC is *2 LUTs*: nine multiply-adds live in DSP slices
      - The FIFO is the largest block: it buys *one pixel per cycle*
      - *94 % of the power* is the static floor of the idle Zynq
    ],
  )
]

#slide[Backup: kernel-size sweep, LUTs and resources][
  #align(center, img("charts/sweep_resources.png", height: 80%))
  #v(-0.2em)
  - *35 routed builds at 160 MHz:* single cascade fewest LUTs, tree the most
]

#slide[Backup: kernel-size sweep, power and Fmax][
  #align(center, img("charts/sweep_performance.png", height: 80%))
  #v(-0.2em)
  - Power: *123 mW at 2×2 to 456 mW at 17×17*; the tree has the higher Fmax from 8×8
]

#slide[Backup: why the FIFO prefills 58 features][
  #grid(columns: (1.35fr, 1fr), column-gutter: 0.9cm,
    align(horizon, img("diagrams/output_fifo.png", width: 100%)),
    [
      - Each row gives W−N+1 features in W cycles: *N−1 gaps*
      - *(W−N)(N−1) = 58* features cover every gap of a frame
      - Built in LUTRAM: *no BRAM*
      - A frame-end mark re-arms it: *no reset*
    ],
  )
]

#slide[Backup: FIFO memory, LUTRAM or block RAM][
  #grid(columns: (1.55fr, 1fr), column-gutter: 0.8cm,
    align(horizon, image("fifo_memory_cost.png", width: 100%)),
    [
      - Chosen at *elaboration*, by cost in the Figure of Merit
      - LUTRAM cost *grows with the image width*
      - A block RAM costs about the same at any size
      - 3×3 kernel: *block RAM from W = 67*
      - Our 32×32 build: *LUTRAM*, 0 BRAM
    ],
  )
]

#slide[Backup: SystemVerilog testbench structure][
  #align(center, img("diagrams/tb_structure.png", width: 74%))
  #v(0.1em)
  - A *reference model inside the testbench* predicts every feature of every lane
  - The *monitor compares every valid output*: 40 configurations × 11 tests
]

#slide[Backup: Python verification software][
  #grid(columns: (1.2fr, 1fr), column-gutter: 0.9cm,
    align(center + horizon, img("verif/conv_lab_architecture.png", width: 100%)),
    [
      - *Four layers*, each importing only the layers below it
      - The *golden model* is NumPy
      - A *file contract* connects Python to QuestaSim: stimulus in, features out
      - The harness compares *bit for bit* and saves an image of every case
      - *62 cases, 87 frames, 0 mismatches*
    ],
  )
]

#slide[Backup: verification in detail][
  #ref-table(
    columns: (2.4fr, auto),
    th[Suite], th[Result],
    [`conv_system_tb`: 40 configurations × 11 tests], [pass],
    [Block testbenches: line buffer, FIFO, kernel register], [pass],
    [Board wrapper `conv_axi_lite_tb` in xsim], [pass],
    [Python unit tests], [100 / 100],
    [Hardware regression: 62 cases, 87 frames], [#verif.cases features],
    [*Mismatching features*], [*0*],
  )
]

#slide[Backup: test images, circle and checkerboard][
  #align(center, grid(columns: (auto, auto), column-gutter: 1.2cm,
    img("verif/cli_circle_128.png", height: 10.9cm), img("verif/cli_checker_128.png", height: 10.9cm)))
  #v(-0.3em)
  #text(size: 18pt)[Rows: Sobel-X, Sobel-Y, Laplacian · columns: input, hardware, golden model · *all match*]
]

#slide[Backup: test images, bars and edges][
  #align(center, grid(columns: (auto, auto), column-gutter: 1.2cm,
    img("verif/cli_bars_128.png", height: 10.9cm), img("verif/cli_edges_128.png", height: 10.9cm)))
  #v(-0.3em)
  #text(size: 18pt)[Rows: Sobel-X, Sobel-Y, Laplacian · columns: input, hardware, golden model · *all match*]
]

#slide[Backup: twelve kernels on one frame][
  #grid(columns: (auto, auto, 1fr), column-gutter: 0.7cm,
    img("verif/cli_edges_12_128_a.png", height: 12.0cm),
    img("verif/cli_edges_12_128_b.png", height: 12.0cm),
    [
      - All *12 preset kernels* as parallel lanes of *one* 128×128 frame
      - Columns: input, hardware, golden model
      - Gradients, Laplacians, blurs, sharpen and emboss on the same edges
      - *190 512 features*, all bit-exact
    ],
  )
]

#slide[Backup: five kernels, and ReLU][
  #grid(columns: (auto, 1fr), column-gutter: 0.9cm,
    img("verif/cli_circle.png", height: 12.0cm),
    [
      #img("verif/cli_checker_relu.png", height: 6.4cm)
      - Left: 32×32 circle through *five kernels* in parallel
      - Above: checkerboard with *ReLU* on the output
      - Every lane: *MATCH*
    ],
  )
]

#slide[Backup: regression test images][
  #grid(columns: (auto, auto, auto, 1fr), column-gutter: 0.6cm,
    img("verif/regression_presets.png", height: 12.0cm),
    img("verif/regression_taps.png", height: 12.0cm),
    img("verif/regression_ties.png", height: 12.0cm),
    [
      #set text(size: 19pt)
      - *Presets:* every preset kernel on the checkerboard
      - *Taps:* one weight at a time, to prove the tap order
      - *Ties:* values exactly on a rounding tie
      - *62 cases, 87 frames, 0 mismatches*
    ],
  )
]
