#import "template.typ": *
#import "results.typ": *

#show: report.with(
  title: [FPGA-Based Edge-AI Vision Accelerator for N×N CNN Convolution],
  subtitle: [Architecture, Verification and FPGA Implementation],
  short-title: [ARA Silicon · Edge-AI CNN Convolution Accelerator],
  team-name: [ARA Silicon],
  university: none,
  supervisor: none,
  members: (
    (name: "Ahmed Ashraf", detail: "Computer Engineering, Graduate",       email: "ahmed.ashraf2827@gmail.com"),
    (name: "Rana Ayman",   detail: "Computer Engineering, Graduate",       email: "ranaayman2468@gmail.com"),
    (name: "Ammar Ahmed",  detail: "Electronics & Communications, Year 4", email: "ammar.a.wahidi@gmail.com"),
  ),
  date: datetime(year: 2026, month: 9, day: 15),
  abstract: [
    Convolution dominates the latency and energy of CNN inference on edge vision devices. This
    report presents `conv_system`, a fully parameterized streaming N×N convolution accelerator for a
    single-channel image, written in SystemVerilog and implemented on the AMD Zynq-7020 (PYNQ-Z2).
    Pixels arrive in raster order; a shift-register line buffer and an N×N register window feed a
    multiply–accumulate (MAC) stage built entirely from DSP48E1 slices. The accelerator contains three
    MAC architectures (a parallel multiplier array with a pipelined adder tree, per-row DSP cascades,
    and one N²-slice PCOUT→PCIN cascade) and elaborates the most efficient one for the kernel size and
    kernel count. Outputs are rounded half up, saturation-safe 16-bit signed features, optionally
    rectified by ReLU, and a prefill FIFO delivers exactly one output pixel per clock cycle. Frames
    stream back to back without a reset: an `o_frame_done` pulse marks the last feature of each
    frame and re-arms the pipeline for the next. The design
    was verified bit-exactly against a Python golden model in QuestaSim across thousands of frames,
    kernel sizes from 3×3 to 11×11 and up to 16 parallel kernels. For the 3×3, 32×32 competition build
    at 250 MHz it uses #fpga.luts LUTs, #fpga.ffs FFs, #fpga.dsps DSPs and no BRAM, reaches
    #perf.fmax MHz and a Figure of Merit of #fix(fom, digits: 5) (bars + Sobel-X) and
    #fix(fom-checker, digits: 5) (checkerboard + Sobel-Y). A PYNQ-Z2 overlay demonstrates the
    accelerator on the board.
  ],
  keywords: ("Edge AI", "CNN accelerator", "FPGA", "DSP48E1 cascade", "Line buffer", "Fixed-point arithmetic"),
  highlights: metric-cards(
    (label: "FoM, checker + Sobel-Y", value: [#fix(fom-checker, digits: 5)]),
    (label: "Fmax", value: [#perf.fmax], unit: "MHz"),
    (label: "LUT + 50 DSP + 100 BRAM", value: [#weighted-area]),
    (label: "Power (checker + Sobel-Y)", value: [#fix(perf.power-total-checker * 1000, digits: 1)], unit: "mW"),
  ),
  draft: false,
)

// ---------------------------------------------------------------------
//  Local helpers
// ---------------------------------------------------------------------
#let fig(path, caption, width: 100%) = figure(image(path, width: width), caption: caption)
#let blk(body, fill: rgb("#dae8fc"), stroke: rgb("#6c8ebf")) = box(
  fill: fill, stroke: 0.7pt + stroke, inset: (x: 8pt, y: 7pt), radius: 3pt,
  align(center, text(size: 8.5pt, body)),
)
#let arrow(label: none) = align(center + horizon, text(size: 7pt, fill: muted)[#if label != none [#label \ ]→])

// =====================================================================
= Design Summary <sec-summary>
// =====================================================================

The table below follows the format required by the competition announcement. All values are for
the competition configuration (N = 3, 32×32 input, one kernel, ReLU off) implemented at a
4.000 ns (250 MHz) clock constraint; @sec-fpga and @sec-perf give the full reports.

#figure(
  caption: [Design summary (required table format)],
  table(
    columns: (1.05fr, 1.1fr, 2.05fr, 0.7fr, 1.35fr),
    table.header[Parameter][Specification][Team Result][Units][Comments],
    [Input image size], [≥ 32 × 32, single channel], [#design.image-w × #design.image-h (parameter `INPUT_SIZE`; 128 × 128 verified)], [pixels], [Output #derived.out-w × #derived.out-h, valid padding],
    [Input precision], [Unsigned fixed-point], [#design.input-bits;-bit unsigned (UQ8.0)], [bits], [Justified in @sec-input-precision],
    [Kernel precision], [8-bit signed], [#design.kernel-bits;-bit signed integer, programmable], [bits], [N × N, `WINDOW_SIZE`],
    [Architecture type], [Multiplier array + pipelined adder tree], [#design.architecture], [—], [MAC chosen from N and K, @sec-mac-select],
    [Multipliers / MACs], [—], [3 architectures, N² DSP48E1 each: \ (1) *Single cascade:* one PCOUT→PCIN chain \ (2) *Row chains:* N-slice chain per row + pipelined adder tree \ (3) *Multiplier array* + pipelined adder tree], [count], [Chosen from N and K (@sec-mac-select); build uses (1): 9 DSP48E1],
    [Pipeline stages], [12 (multiplier array + pipelined adder tree)], [#design.pipeline-stages], [stages], [Pixel path; @tab-latency],
    [Latency], [—], [#val(perf.latency) (frame warm-up); #design.pipeline-stages per pixel], [cycles], [First pixel → first feature, @sec-perf],
    [Throughput], [1], [#perf.throughput (sustained)], [px / cycle], [One output pixel per clock cycle],
    [FPGA utilization], [—], [LUT #fpga.luts, FF #fpga.ffs \ DSP #fpga.dsps, BRAM #fpga.brams], [—], [#fpga.device],
    [Maximum frequency], [250 MHz], [#perf.fmax (WNS +#fix(perf.wns) ns at 4.000 ns)], [MHz], [Timing met],
    [Power estimate], [—], [#fix(perf.power-total-checker, digits: 4)], [W], [Checkerboard + Sobel-Y benchmark, routed, SAIF],
    [Verification status], [Matches golden model], [#verif.status], [—], [0 mismatches, @sec-verif],
    [FOM], [Higher is better], [*#fix(fom-checker, digits: 5)*], [px/(cycle·W)], [@eq-fom; checkerboard + Sobel-Y benchmark],
  ),
) <tab-summary>

// =====================================================================
= Introduction <sec-intro>
// =====================================================================

== Background and Motivation

Convolution layers account for most of the arithmetic of a CNN. On an edge smart device the
computation has to meet a latency target inside a tight power and cost budget, which rules out
frame-buffered processors that copy whole images between memory and compute. An FPGA can instead
process pixels as they arrive from a sensor, keep only the rows a kernel needs, and map every
multiplication onto hardened DSP slices, so a small device reaches hundreds of megapixels per second
at around a hundred milliwatts.

The competition scores designs with a Figure of Merit that rewards throughput per watt per
weighted resource, where a DSP slice costs 50 LUTs and a block RAM 100. Our work therefore
concentrated on three questions: which MAC structure minimizes the weighted resource count without
losing one-output-pixel-per-cycle throughput, how to keep the memory entirely out of block RAM, and
how to prove the result bit-exact against an independent golden model. We built and measured nine
distinct MAC and datapath variants before arriving at the final design (@sec-tradeoffs).

== Contributions

- A streaming N×N convolution accelerator whose MAC stage contains *three architectures* and
  elaborates the best one for the kernel size N and kernel count K (@sec-mac-select).
- Three MAC architectures built on DSP48E1 slices:
  + a *single PCOUT→PCIN cascade* in which every addition is a DSP post-add, so the 3×3 MAC uses
    2 LUTs (@sec-mac-chain);
  + *row DSP chains*, one N-slice cascade per window row followed by a pipelined adder tree;
  + a *multiplier array* of N² parallel DSPs followed by a pipelined binary adder tree.
- *Zero BRAM*: SRL line buffer, register window, LUTRAM output FIFO chosen automatically by its
  figure-of-merit cost.
- *Sustained 1 output pixel per clock cycle* with arbitrary input stalls, from a prefill FIFO sized
  to one frame's row-edge gaps.
- *Continuous multi-frame streaming without reset*: frames follow each other back to back, the last
  feature of each frame carries an `o_frame_done` pulse, and a new kernel can be loaded between
  frames, for zero extra LUTs in the frame-end mark (@sec-fsm).
- *Round-half-up* 16-bit output whose saturation logic is built only when it is reachable (@sec-fixed).
- A two-level verification flow: a self-checking SystemVerilog testbench swept over 168
  configurations, and a Python golden model driving the RTL in QuestaSim through a regression of
  53 cases plus image-level edge-detection demos (@sec-verif).
- A scripted Vivado flow (synthesis, implementation, SAIF power, FoM) and a PYNQ-Z2 board overlay
  with a Python driver (@sec-bonus).
- *All optional bonus features* of the competition: ReLU activation, one output pixel per clock
  cycle, multiple kernels (1–16 verified), a PYNQ-Z2 board demonstration and an
  edge-detection / industrial-inspection demo (@tab-bonus).

== Competition Specifications

#figure(
  caption: [Specification compliance matrix],
  table(
    columns: (auto, 1fr, 1.9fr, auto, auto),
    align: (center, left, left, left, center),
    table.header[\#][Specification][Our implementation][Addressed in][Status],
    [1], [Input image size], [`INPUT_SIZE` parameter; 32×32 competition build, 4×4 to 128×128 simulated, grayscale single channel], [@sec-arch], status("met"),
    [2], [Input precision], [8-bit unsigned fixed point, justified], [@sec-input-precision], status("met"),
    [3], [Kernel size], [N × N, `WINDOW_SIZE` parameter, weights loaded at run time through the stream interface], [@sec-memory], status("met"),
    [4], [Kernel precision], [8-bit signed integer weights], [@sec-fixed], status("met"),
    [5], [Stride], [Stride 1: every accepted pixel after warm-up completes one window], [@sec-window], status("met"),
    [6], [Output precision], [16-bit signed; exact accumulator, fixed scale 2#super[−clog2(N²)], round half up, saturation analysed], [@sec-fixed], status("met"),
    [7], [Activation], [ReLU per kernel lane, `ENABLE_RELU` parameter], [@sec-relu], status("bonus"),
    [8], [Verification], [Python golden model, SystemVerilog testbenches, expected versus hardware values (@tab-samples), image comparisons, waveforms], [@sec-verif], status("met"),
    [9], [FPGA results], [LUT, FF, DSP, BRAM, Fmax, timing, SAIF-based power from routed design], [@sec-fpga], status("met"),
    [10], [Figure of Merit], [Reported on two workloads and the vectorless estimate], [@sec-perf], status("met"),
  ),
) <tab-compliance>

== Design Assumptions <sec-assumptions>

The announcement leaves several points open; we state our interpretation of each.

#assumption[Convolution is implemented as cross-correlation (no kernel flip), as in CNN frameworks,
with "valid" padding: an H × W image and an N × N kernel give $(H - N + 1) times (W - N + 1)$
outputs, #derived.out-w × #derived.out-h for the competition build. Images are square.]

#assumption[Pixels arrive as a raster-order stream (row by row, left to right) with a valid
strobe that may be deasserted at any time (stalls). A frame starts with its first `i_pixel_valid`
and ends with `o_frame_done`, which is high together with `o_valid` on the frame's last feature;
the next `i_pixel_valid` starts the next frame, with no reset in between, and may follow the
previous frame's last pixel immediately. A reset is needed only at power-up or to abandon a
partial frame.]

#assumption[The kernel coefficients are written before a frame starts and stay constant during
the frame; a new kernel may be loaded between frames, after `o_frame_done`, without a reset. They
arrive on the same 8-bit data bus as the pixels, qualified by a weight-valid strobe and a
kernel-select index.]

#assumption[The output is the exact window sum scaled by a fixed $2^(-ceil(log_2 N^2))$
(a 4-bit right shift for 3×3) with round half up. Kernels are therefore expressed in integer form;
a kernel whose weights sum to 16 has unity gain at 3×3.]

#assumption[Throughput is the number of output pixels per clock cycle in steady-state streaming
(1.0 for this design). Latency is reported both as the pipeline depth of one pixel and as the
number of cycles from the first input pixel to the first output feature of a frame.]

#assumption[Power in the FoM is the *total on-chip power* reported by Vivado for the routed design,
in watts, including the device static power of the Zynq. Switching activity comes from a SAIF file
recorded while one full frame streams through the RTL at 250 MHz. We report two workloads, bars +
Sobel-X and a pixel checkerboard + Sobel-Y, plus Vivado's vectorless estimate for reference.]

#assumption[The FoM is evaluated for the competition configuration: N = 3, 32 × 32, one kernel,
ReLU off, on the PYNQ-Z2 part `xc7z020clg400-1`, as a programmable-logic design driven directly by
its ports. The processing system is only used in the optional board demonstration.]

== Report Organization

@sec-arch presents the architecture and its interface. @sec-memory covers the kernel register,
line buffer and window generation, and @sec-datapath the three MAC architectures, rounding, ReLU and
output FIFO. @sec-fsm describes the valid-driven control, @sec-fixed the bit-width analysis and
@sec-rtl the RTL. @sec-verif documents verification, @sec-fpga the FPGA results and @sec-perf the
latency, throughput and FoM. @sec-bonus lists the bonus features, @sec-tradeoffs the design-space
exploration and trade-offs, and @sec-conclusion concludes.

// =====================================================================
= Accelerator Architecture <sec-arch>
// =====================================================================

== Top-Level Overview

`conv_system` is a *streaming* accelerator: it never stores a frame. Every stage forwards a valid
bit with its data, so the image flows through the pipeline at the rate it arrives
(@fig-arch-blocks).

+ *Input registers* capture the 8-bit data bus and the two valid strobes.
+ The *line buffer* keeps the previous N − 1 rows; the current row is taken live from the input.
+ The *window generator* shifts those N rows into an N × N register window and asserts
  `window_valid` once enough rows and columns have arrived.
+ The *kernel register* of each lane holds N² programmable 8-bit signed weights.
+ The *MAC* multiplies every window tap by its weight and sums the N² products in DSP48E1 slices.
+ *Round & saturate* narrows the exact sum to 16 bits with round half up.
+ An optional *ReLU* clamps negative features.
+ The *output FIFO* absorbs the gaps at every row edge and emits one feature per clock cycle.

The front end (input registers, line buffer, window) is shared. Everything from the kernel register
onward is one *lane* per kernel and is replicated `NUM_KERNELS` times; all lanes see the same window
on the same cycle, so K kernels cost K MACs but no extra memory or latency.

#fig("figures/diagrams/arch_blocks.png", [Block-level architecture of `conv_system`. Solid arrows carry data, dashed arrows valid and control. The dashed region is replicated per kernel.]) <fig-arch-blocks>

@fig-arch-detailed, at the end of this section, shows the register-level microarchitecture for any
kernel size N, image width W and kernel count K: the N − 1 SRL banks of the line buffer, the N × N
window, the shift-loaded kernel register, the three MAC options of which one is generated per lane,
the two-stage round/saturate, the optional ReLU and the FIFO with its prefill and frame-end logic.
Its legend gives the colour code of registers, memories, DSP slices and MAC options.

== Interface and I/O Protocol

#figure(
  caption: [`conv_system` ports],
  table(
    columns: (auto, auto, auto, 1fr),
    table.header[Signal][Dir.][Width][Description],
    [`clk`], [in], [1], [System clock (4.000 ns constraint)],
    [`rst_n`], [in], [1], [Active-low asynchronous reset: power-up, or to abandon a partial frame],
    [`i_data`], [in], [8], [Pixel (unsigned) or weight (signed) — shared bus],
    [`i_pixel_valid`], [in], [1], [`i_data` is the next pixel in raster order; may stall],
    [`i_weight_valid`], [in], [1], [`i_data` is the next weight of the selected kernel],
    [`i_select_kernel`], [in], [⌈log₂K⌉ + 1], [Kernel lane loaded by weight writes],
    [`o_feature[K]`], [out], [16 each], [Signed output feature of every lane],
    [`o_valid`], [out], [1], [All `o_feature` lanes valid (lanes advance in lockstep)],
    [`o_frame_done`], [out], [1], [High with `o_valid` on the last feature of every frame],
  ),
) <tab-ports>

After reset, the host writes N² weights per lane (selecting the lane with `i_select_kernel`).
Every frame is then W² pixel writes, with any number of idle cycles between them, and its
(W − N + 1)² features appear on `o_feature` with `o_valid`; the last one also carries
`o_frame_done`. The next frame follows *without a reset*, back to back or after any gap, and a new
kernel can be written between frames. Weights are written row by row and, within a row, from right
to left (@sec-window explains why).

== Parameters

#figure(
  caption: [Top-level parameters of `conv_system`],
  table(
    columns: (auto, auto, 1fr),
    table.header[Parameter][Default][Meaning],
    [`PIXEL_WIDTH`], [8], [Pixel and weight width],
    [`WINDOW_SIZE`], [3], [Kernel size N],
    [`INPUT_SIZE`], [32], [Image width W (square image)],
    [`FEATURE_WIDTH`], [16], [Output width],
    [`NUM_KERNELS`], [1], [Parallel kernel lanes K],
    [`ENABLE_RELU`], [0], [Insert `relu_unit` per lane],
    [`FIFO_RAM_MODE`], [0], [Output FIFO memory: 0 automatic, 1 LUTRAM, 2 BRAM],
    [`MAC_ARCH`], [0], [0 automatic, 1 tree, 2 row chains, 3 single chain],
    [`CHAIN_MAX_N`, `ROW_CHAIN_MAX_N`, `ROW_CHAIN_MAX_DSP`], [3, 8, 180], [Limits of the automatic MAC selection],
  ),
) <tab-params>

== Key Architectural Decisions

- *Streaming, not frame-buffered.* Storing N − 1 rows instead of the frame keeps memory at
  (N − 1) × W × 8 bits (512 bits at 3 × 3 / 32) and allows one output per input pixel.
- *All arithmetic in DSP48E1 slices.* Nine 8 × 8 multiplications in fabric cost about 87 LUTs each
  (measured: 933 LUTs, timing failed), far above the 50 LUTs a DSP is worth in the FoM. Moving the
  additions into the DSP post-adders as well removed the fabric adder tree, the largest LUT consumer
  of the baseline (139 of 243 LUTs).
- *No block RAM.* One BRAM costs 100 FoM points, more than the whole LUT count of the final design;
  line buffer and FIFO use SRLs and LUTRAM.
- *Architecture chosen by elaboration.* No single MAC is best at every kernel size: the single
  cascade needs the fewest LUTs but its tap-alignment flip-flops grow as N⁴ (@sec-mac-select).
- *FIFO for one pixel per cycle.* A window becomes invalid for N − 1 pixels at every row edge; a
  small prefill FIFO turns the gapped stream into a continuous one, a bonus requirement.
- *Frames back to back without reset.* A one-hot row ring in the line buffer and a flip-flop delay
  line carry the frame-end mark to the FIFO with the last feature, which re-arms the prefill and
  raises `o_frame_done`. Both cost flip-flops, which the FoM does not charge, instead of LUT-based
  counters (@sec-fsm).

#page(flipped: true)[
  #figure(
    image("figures/diagrams/arch_detailed.png", width: 100%),
    caption: [Register-level microarchitecture of `conv_system`, generic in N, W and K. Stages ① to ⑦ follow the data from the input registers to the output FIFO; stage ④ generates one of the three MAC options per lane, and the strip below gives the latency each stage adds.],
  ) <fig-arch-detailed>
]

// =====================================================================
= Memory Organization and Window Generation <sec-memory>
// =====================================================================

== Kernel Coefficient Storage

Each lane has a `kernel_register` holding N² signed 8-bit weights in flip-flops (72 bits at 3 × 3).
Weights are *shift-loaded*: every weight write shifts the register by one position, so there is no
write pointer or address decoder (5 LUTs instead of 16 for an indexed write). A load counter raises
`o_ready` after N² writes; the MAC only accepts windows once every lane is ready. A write while
`o_ready` is high starts a new load (the counter restarts at one), so a kernel can be replaced
between frames without a reset, while an over-long load leaves `o_ready` low. Because weights
are static during a frame they need no pipeline alignment and are registered once more into each
DSP slice's B port (BREG).

#fig("figures/diagrams/kernel_register.png", [Shift-loaded kernel register. The lane enable is the weight-valid strobe qualified by the kernel-select index.], width: 88%) <fig-kernel>

== Line Buffers

The line buffer stores N − 1 = 2 rows of W = 32 pixels in shift-register LUTs (SRLC32E, attribute
`srl_style = "srl"`): 2 × 32 × 8 = 512 bits in 16 SRLs. All banks shift on the pixel write enable,
so a stall simply freezes them. Bank 0 delays the input by one row and bank 1 by two rows; the
current row is not stored at all but passed straight to the window generator. A column counter
marks the end of each row. The row position within the frame is a *one-hot ring* of W flip-flops
that rotates at every row end. A ring needs no incrementer and no comparator, so the frame position
costs flip-flops only, which the FoM does not charge; a 5-bit binary row counter measured 4 LUTs
more. A registered `rows_ready` is set when row N − 2 completes and cleared when the frame's last
row completes, so the next frame refills both banks before its first window and no pixel of one
frame ever enters a window of the next. The ring's last bit also marks the write of the frame's
last pixel with a registered `o_frame_end` pulse, on the cycle the frame's last window becomes
valid. The whole module is 22 LUTs.

#fig("figures/diagrams/line_buffer.png", [Line buffer: two SRL banks of 32 taps × 8 bits and the live row feed the 3 × 3 window; the column counter and one-hot row ring produce `rows_ready` and the frame-end mark.]) <fig-linebuf>

@fig-lbw follows the pixels through the buffer. The new pixel enters the live row of the window,
bank 0 supplies the pixel one row above it and bank 1 the pixel two rows above, so every write moves
the N × N window one column along the raster scan of the image.

#fig("figures/diagrams/line_buffer_window.png", [Line buffer and window operation (N = 3). The live pixel and the two SRL banks feed one shift register per window row (drawn vertically); their nine taps form the window. Right: the window on the image when the newest pixel (bold) is written.]) <fig-lbw>

We also built a LUTRAM ring buffer (same-address read/write). It saved 8 LUTs at 3 × 3 / 32 and 96
at 13 × 13 / 64, but its column address toggles into every RAM LUT, adding 1.1–1.9 mW (5.5 mW at
13 × 13), so the FoM moved by −0.5 % to +0.3 % and the SRL buffer was kept. A BRAM line buffer only
pays off for rows of roughly 128–256 pixels.

== Sliding-Window Generation <sec-window>

The window generator is an N × N array of 8-bit registers, one shift register per row, fed by the
N line-buffer taps (@fig-window). On every accepted pixel all rows shift by one column, which gives
*stride 1*. A column counter, reset at every row end, and `rows_ready` produce `window_valid`, so
the (N − 1) partial windows at the start of each row are never presented to the MAC.

*Tap order.* A new column enters at column index 0, so the flattened window is row-ascending but
column-descending: `o_window[i·N + j] = image[r + i][c + N − 1 − j]`. Loading a kernel verbatim
would therefore compute a column-mirrored correlation. The host writes each kernel row right to
left, which restores the natural correlation. This is invisible on symmetric kernels (box, Gaussian,
Laplacian) and appears only as a sign flip on Sobel-X; dedicated one-hot tap tests catch it
(@sec-test-cases).

#fig("figures/diagrams/window_generator.png", [Window generator: 3 × 3 register window, column counter and window-valid register.], width: 92%) <fig-window>

// =====================================================================
= Datapath <sec-datapath>
// =====================================================================

The multiply–accumulate stage is where most of our design work went, and it is generic.
`conv_system` contains three complete MAC architectures, all designed by the team, each
parameterized in the kernel size N and replicated for every kernel lane. None of them is tied to the
3 × 3 competition point: all three are verified across kernel sizes and kernel counts
(@sec-verif), and the Figure-of-Merit build uses the single cascade only because the selection of
@sec-mac-select picks it at N = 3, K = 1. @tab-mac-generic compares how the three scale with N.

#figure(
  caption: [The three MAC architectures as functions of the kernel size N (per lane)],
  table(
    columns: (1fr, 1fr, 1.15fr, 1fr),
    table.header[][Single cascade][Row chains][Multiplier array + tree],
    [`MAC_SEL`], [3], [2], [1],
    [DSP48E1 slices], [N²], [N²], [N²],
    [Additions], [DSP post-adders only], [DSP post-adders + N − 1 fabric adders], [N² − 1 fabric adders],
    [Skew flip-flops], [grow as N⁴], [grow as N³], [none],
    [Registered adder levels], [—], [⌈log₂N⌉], [⌈log₂N²⌉],
    [Latency (cycles)], [2 + N²], [2 + N + ⌈log₂N⌉], [3 + ⌈log₂N²⌉],
    [DSP placement], [one column of N² slices], [one short column per row], [free; may spill into fabric],
    [Selected for], [K = 1, N ≤ 3], [K = 1, 4 ≤ N ≤ 8; K ≥ 2, 2 ≤ N ≤ 8, N²·K ≤ 180], [every other N, K],
    [3 × 3 LUT / FF (@tab-arch3)], [70 / 474], [110 / 322], [205 / 429],
  ),
) <tab-mac-generic>

== DSP48E1 Slice Configuration

All three MAC architectures are built from the same DSP48E1 slice. @fig-ug369 shows the full
primitive and @fig-dsp the configuration used in every MAC:
the pixel, zero-extended to 9 bits, enters port A and the weight port B; the product is registered
in MREG and added in the post-adder to either nothing (first slice), the carry-in port C or the
partial sum arriving on the dedicated PCIN cascade, and registered in PREG. Both MREG and BREG are
required: with the multiply and post-add in one combinational stage the slice missed 250 MHz by
0.644 ns.

#fig("figures/diagrams/dsp48e1_ug369.png", [The DSP48E1 slice primitive: 25 × 18 multiplier, A, B, C and D inputs with the optional pre-adder, 48-bit arithmetic unit and the dedicated PCIN/PCOUT cascade (reproduced from Xilinx UG369 [8]).], width: 88%) <fig-ug369>

#fig("figures/diagrams/dsp48e1_slice.png", [DSP48E1 slice as configured in every MAC: registered pixel and weight inputs, registered product (MREG) and post-adder result (PREG). The partial sum enters on PCIN and leaves on PCOUT.], width: 72%) <fig-dsp>

== Single DSP Cascade <sec-mac-chain>

`mac_single_chain` places all N² slices in one PCOUT→PCIN chain (@fig-chain): slice e computes
$"acc"_e = "acc"_(e-1) + p_e dot w_e$ in its post-adder. There are no fabric adders; the module uses
2 LUTs. Because the partial sum advances one slice per cycle, tap e must be delayed by e + 1 cycles
so that all products belong to the same window. These *skew registers* are flip-flops
(`srl_style = "register"`, the last two absorbed into the slice's AREG), which the FoM does not
charge: 226 FFs at 3 × 3. The latency is 2 + N² = 11 cycles. The chain must fit in one DSP column
(the xc7z020 columns hold 20, 20, 60, 60 and 60 slices).

#fig("figures/diagrams/mac_single_chain.png", [Single cascade (N = 3): nine DSP48E1 slices in one PCOUT→PCIN chain, drawn three per row. Tap e passes e skew flip-flops and the slice's AREG, the weight enters BREG, and the partial sum advances one PREG per slice.]) <fig-chain>

== Row DSP Chains

`mac_row_chain` builds one chain of N slices per window row and reduces the N row sums in a short
fabric adder tree (@fig-rowchain). Skew grows only as N³ (9 · N · N(N + 1)/2 bits), and the tree
widths grow one bit per level (row sums enter at 16 + ⌈log₂N⌉ bits), which saved 14 LUTs and 11 FFs
at 7 × 7. The tree carries `use_dsp = "no"`; otherwise Vivado absorbs one add into a tenth DSP,
costing 50 points to save about 20 LUTs. Latency: 2 + N + ⌈log₂N⌉.

#fig("figures/diagrams/mac_row_chain.png", [Row chains (N = 3): one three-slice PCOUT→PCIN cascade per window row, with the same slice internals as @fig-chain, and a two-stage pipelined fabric adder tree over the 18-bit row sums.]) <fig-rowchain>

== Multiplier Array and Adder Tree

The classic structure (`multiplier_array` + `adder_tree`) computes the N² products in parallel
DSPs (A/B → M → P, three register stages) and sums them in a pipelined binary tree of ⌈log₂N²⌉
registered levels, one bit wider per level: 9 → 5 → 3 → 2 → 1 with 17, 18, 19 and 20 bits at 3 × 3
(@fig-tree). It is the only architecture whose multipliers can spill into fabric when the device runs
out of DSPs, which makes it the choice for large kernels. Latency: 3 + ⌈log₂N²⌉ = 7 at 3 × 3.

#fig("figures/diagrams/mac_tree.png", [Multiplier array and four-level pipelined adder tree (9 → 5 → 3 → 2 → 1).]) <fig-tree>

== Automatic MAC Selection <sec-mac-select>

Every MAC needs N² × K DSPs, but the three differ in LUTs, in flip-flops and in how they fail. The
selection is a pure elaboration-time function of N and K (@fig-macsel, @tab-macsel). The limits sit
one step inside the measured failure points (@sec-scaling) as margin: row chains closed 250 MHz up to
9 × 9, the single chain up to 7 × 7, and the device has 220 DSPs. `MAC_ARCH` can force a choice.

#figure(
  caption: [MAC architecture selected per kernel size N and kernel count K],
  table(
    columns: (auto, 1fr, 1fr),
    table.header[Kernels][Condition][Architecture],
    [K = 1], [N ≤ 3], [single DSP cascade],
    [K = 1], [4 ≤ N ≤ 8], [row chains],
    [K = 1], [N ≥ 9], [multiplier array + adder tree],
    [K ≥ 2], [2 ≤ N ≤ 8 and N² · K ≤ 180], [row chains],
    [K ≥ 2], [otherwise], [multiplier array + adder tree],
  ),
) <tab-macsel>

#fig("figures/diagrams/mac_selection.png", [Elaboration-time MAC selection from the kernel size N and the kernel count K.], width: 62%) <fig-macsel>

The single-chain build also adds `(* max_fanout = 24 *)` to the pixel write-enable register, which
drives about 97 clock enables: the long DSP column stretches the placement, and duplicating the
register raised the slack from +0.386 ns to +0.757 ns at no LUT cost.

== Output Stage: Round and Saturate

`round_saturate` narrows the ACCUM\_WIDTH-bit sum to 16 bits in two register stages
(@fig-roundsat). Stage A splits the sum into the truncated value `x[19:4]` and the guard bit `x[3]`;
stage B adds the guard bit (round half up, @sec-fixed). The positive clamp is generated only when
the maximum reachable sum could overflow after rounding, which @sec-overflow shows never happens for
8-bit data, so no overflow or clamp logic is built (2 LUTs).

#fig("figures/diagrams/round_saturate.png", [Round and saturate: stage A registers the truncated value and the guard bit, stage B the rounded 16-bit feature. The dashed clamp is elaborated only when reachable.]) <fig-roundsat>

== ReLU Activation <sec-relu>

With `ENABLE_RELU = 1` each lane inserts `relu_unit`, one register stage that outputs 0 when the
sign bit is set. Placing it after rounding is exact because rounding is monotonic and maps 0 to 0,
and the sign decision is made on 16 instead of 20 bits. Without ReLU the stage is a wire.

== Output FIFO and One Pixel per Cycle

The MAC output is invalid for N − 1 cycles at every row edge. `output_fifo` stores
PREFILL = (W − N)(N − 1) = 58 features before it starts reading, exactly one frame's worth of
row-edge gaps, after which `o_valid` stays high until the frame is drained: one output pixel per
clock cycle (@fig-fifo). The RAM is the next power of two (64 × 16 bits) with self-wrapping
pointers, so "empty" is a pointer comparison. The memory type is chosen at elaboration by comparing
the FoM cost of LUTRAM (LUTs) with that of BRAM (tile cost plus its power converted to resource
points); the competition build uses 24 LUTRAMs and 19 logic LUTs, 6 of them for the frame re-arm
described below.

*Frame end.* The frame's last feature arrives with the frame-end mark (@sec-fsm) and sets a
`q_last_written` flag. From then on the FIFO is not empty again until that feature has been read,
so `o_last` (`o_frame_done`) is simply _prefilled ∧ last written ∧ empty_, true exactly on the cycle
`o_valid` presents the last feature. It reuses the FIFO's empty comparator and needs no pointer
arithmetic. One cycle later a registered clear drives the synchronous reset of the pointers and
flags, so the next frame is prefilled and drained exactly like the first one, without a reset.
Registering the clear mattered: merged into the pointers' next-state logic the frame end cost 18
LUTs, and driven straight from the comparator onto the reset pins it became the critical path
(synthesis WNS +0.026 ns); registered it costs 6 LUTs and synthesis slack returns to +0.664 ns.
The next frame cannot reach the
FIFO earlier: its first feature needs (N − 1)(W + 1) + 1 = 67 accepted pixels, more than the at most
58 features still to drain, and a simulation assertion checks it. The prefill threshold is capped
at the frame's feature count, so frames smaller than their row-edge gap count (e.g. 7 × 7 on
8 × 8) still drain.

#fig("figures/diagrams/output_fifo.png", [Output FIFO: prefill and read logic, frame-done detection and the registered clear that re-arms it for the next frame. LUTRAM or BRAM is selected by figure-of-merit cost.], width: 92%) <fig-fifo>

// =====================================================================
= Control <sec-fsm>
// =====================================================================

`conv_system` has *no central FSM state register*. Every stage forwards a valid bit alongside its
data, and the phases of a frame are decoded from counters that the datapath needs anyway: the
kernel load counter, the line-buffer column counter and one-hot row ring, the window column counter
and the FIFO pointers and flags. This keeps the control out of the critical paths and makes
stalls free: when `i_pixel_valid` drops, every counter and shift register simply holds. @fig-fsm
shows the resulting implicit state machine and @tab-fsm its states. The machine is a loop: after a
frame's last feature it returns to `FILL_LINES` for the next frame (or to `LOAD_KERNEL` for a new
kernel); `RESET` is entered only at power-up or to abandon a partial frame.

#fig("figures/diagrams/control_fsm.png", [Implicit frame state machine decoded from existing counters. Frames loop back to `FILL_LINES` on `o_frame_done` without a reset.]) <fig-fsm>

#figure(
  caption: [Implicit control states and the signals that encode them],
  table(
    columns: (auto, 1.7fr, 1.5fr),
    table.header[State][Behaviour][Encoded by / exit condition],
    [`RESET`], [All counters, pointers, flags and the frame-end mark cleared (power-up or abandoned frame)], [`rst_n` low],
    [`LOAD_KERNEL`], [Weights shift into the selected lane; also between frames], [`r_loaded_cnt < N²`; exit when every lane is ready],
    [`FILL_LINES`], [Pixels of a new frame fill the line buffer, no window yet], [`rows_ready = 0` (ring before row N − 1)],
    [`FILL_WINDOW`], [First N − 1 columns of each row], [`r_col_cnt < N − 1`],
    [`STREAM`], [One window per accepted pixel through MAC, rounding, ReLU], [`window_valid` and all kernels ready],
    [`PREFILL`], [FIFO stores features, no output], [`q_prefilled = 0` until 58 writes],
    [`OUTPUT`], [One feature per cycle while data is buffered], [`q_prefilled = 1` and FIFO not empty],
    [`DRAIN`], [Last pixel written, FIFO empties], [read of the last feature: `o_frame_done`, then `FILL_LINES`],
  ),
) <tab-fsm>

*Frame boundary.* The only new control for continuous streaming is a mark that travels with the
frame's last window. `line_buffer` raises `o_frame_end` on the cycle the last window becomes valid.
Every stage behind the window forwards valid through a fixed number of registers — the MAC
(2 + N² = 11 cycles for the single cascade, 2 + N + ⌈log₂N⌉ for row chains, 3 + ⌈log₂N²⌉ for the
tree), round/saturate (2) and ReLU (1 when enabled) — so a reset flip-flop chain of that length,
`LAST_DELAY` = 13 at 3 × 3, delivers the mark to the FIFO together with the last feature. A
simulation assertion checks that the mark always meets a feature. Because the mark is a plain
flip-flop chain it adds no LUTs, and the FoM does not charge flip-flops.

// =====================================================================
= Fixed-Point Bit-Width Analysis <sec-fixed>
// =====================================================================

== Number Formats

#figure(
  caption: [Fixed-point formats along the datapath (3 × 3)],
  table(
    columns: (1.2fr, auto, auto, 1.5fr),
    align: (left, left, center, left),
    table.header[Signal][Type][Width][Range],
    [Input pixel], [Unsigned], [#design.input-bits], [\[0, #derived.in-max\]],
    [DSP A operand], [Signed], [9], [\[0, #derived.in-max\] (zero-extended)],
    [Kernel coefficient], [Signed], [#design.kernel-bits], [\[#derived.k-min, #derived.k-max\]],
    [Product], [Signed], [#derived.prod-bits], [\[#derived.prod-min, #derived.prod-max\]],
    [Accumulator (exact sum)], [Signed], [#derived.acc-bits], [\[#derived.acc-min, #derived.acc-max\]],
    [Output feature], [Signed], [#design.output-bits], [\[#derived.out-min, #derived.out-max\]],
    [Reachable output], [Signed], [#design.output-bits], [\[−18360, 18217\]],
  ),
) <tab-formats>

== Accumulator Word Growth

The product of an 8-bit unsigned pixel and an 8-bit signed weight fits 16 signed bits. A sum of N²
products needs ⌈log₂N²⌉ guard bits, so the accumulator is exact and can never wrap:

$ W_"acc" = W_"in" + W_"k" + ceil(log_2 N^2) = 8 + 8 + #derived.growth-bits = #derived.acc-bits "bits" $ <eq-acc>

Inside the DSP cascade the 48-bit P register holds the partial sums with wide margin; in the row
chains and the adder tree each level grows by exactly one bit, so no intermediate result is wider
than needed.

== Scaling, Rounding and Truncation

The accumulator is wider than the 16-bit output by DROP = W#sub[acc] − 16 = ⌈log₂N²⌉ bits (4 at
3 × 3). The output is the sum scaled by $2^(-"DROP")$ with *round half up*:

$ y = floor((x + 2^("DROP" - 1)) / 2^"DROP") = x["W"_"acc"-1 : "DROP"] + x["DROP" - 1] $ <eq-round>

i.e. the truncated value plus the first discarded (guard) bit — one incrementer, no sticky logic.
Ties go toward +∞ (4.5 → 5 and −4.5 → −4). Plain truncation would bias every output by −0.5 LSB;
round-half-to-even needs the sticky OR of the discarded bits and was replaced after we measured it
in an earlier build. This fixed scale is a built-in normalization: a 3 × 3 kernel with weights summing
to 16 (Gaussian, sharpen, identity with centre 16) has unity gain.

== Overflow and Saturation <sec-overflow>

Saturation is analysed at elaboration time from the largest reachable positive sum,

$ x_max = N^2 dot (2^8 - 1) dot (2^7 - 1) = 9 dot 255 dot 127 = 291465, $

which rounds to (291465 + 8) ≫ 4 = 18217 < 32767. The most negative sum, 9 · 255 · (−128) = −293760,
gives −18360 > −32768. In general DROP = ⌈log₂N²⌉ ≥ log₂N², so |y| ≤ 255 · 128 = 32640 for *every*
N: the 16-bit output can never overflow with 8-bit data. `round_saturate` receives
`IN_MAX = ACCUM_MAX` and builds the clamp (a flag in stage A and a mux in stage B) only when
$(x_max + 2^("DROP"-1)) ≫ "DROP"$ exceeds the output range; it is generated if `PIXEL_WIDTH` or
`FEATURE_WIDTH` is changed. An exhaustive unit test drove all 2#super[20] inputs of a 20-to-16-bit
instance, where the clamp is reachable, against a definition-level model.

== Input Precision Justification <sec-input-precision>

We chose 8-bit unsigned (UQ8.0) pixels:

- *Source format.* Grayscale sensors and image files deliver 8 bits per pixel; 256 levels are
  above the roughly 100 just-noticeable grey levels of human vision and match the 8-bit activations
  of quantized CNNs.
- *DSP fit.* An 8-bit pixel zero-extended to 9 bits and an 8-bit weight use a small part of the
  DSP48E1's 25 × 18 multiplier, leaving the 48-bit post-adder free for accumulation.
- *Word growth.* Each extra input bit widens every product, the accumulator and the skew
  registers; 8 bits keeps the 3 × 3 accumulator at 20 bits and the output provably inside 16 bits
  (@sec-overflow).
- *Fewer bits* (e.g. 6) would save little: the multipliers are DSPs either way and the LUT count
  of the datapath is already 2, so only flip-flops (not charged by the FoM) would shrink, at a
  visible loss of contrast on natural images.

`PIXEL_WIDTH` remains a parameter; the widths of every stage and the clamp decision follow it.

// =====================================================================
= RTL Implementation <sec-rtl>
// =====================================================================

== Module Hierarchy

#figure(
  caption: [RTL modules (`hw/`) and their routed resources in the competition build],
  table(
    columns: (auto, 1.6fr, auto, auto, auto),
    align: (left, left, right, right, right),
    table.header[Module][Function][LUT][FF][DSP],
    [`conv_system`], [Top level, input registers, MAC selection, lane replication, frame-end delay line], [0], [38], [0],
    [`line_buffer`], [N − 1 SRL row buffers, column counter, one-hot row ring, frame-end mark], [22], [39], [0],
    [`window_generator`], [N × N register window, window valid], [3], [75], [0],
    [`kernel_register`], [Shift-loaded N² × 8-bit weights, ready flag], [5], [76], [0],
    [`mac_single_chain`], [N²-slice PCOUT→PCIN cascade (MAC\_SEL 3)], [2], [226], [9],
    [`mac_row_chain`], [Row cascades + bit-growing tree (MAC\_SEL 2)], [—], [—], [—],
    [`multiplier_array`, `adder_tree`], [Parallel multipliers + pipelined tree (MAC\_SEL 1)], [—], [—], [—],
    [`round_saturate`], [Round half up, clamp only when reachable], [3], [35], [0],
    [`relu_unit`], [Optional ReLU], [—], [—], [—],
    [`output_fifo`], [Prefill FIFO, LUTRAM or BRAM, frame re-arm and `o_frame_done`], [43], [32], [0],
    [*Total*], [], [*#fpga.luts*], [*#fpga.ffs*], [*#fpga.dsps*],
  ),
) <tab-modules>

== Parameterization

#figure(
  caption: [Header of the top-level module (`hw/system/conv_system/src/rtl/conv_system.sv`)],
  ```systemverilog
  module conv_system #(
     parameter int PIXEL_WIDTH   = 8,
     parameter int WINDOW_SIZE   = 3,
     parameter int INPUT_SIZE    = 32,
     parameter int FEATURE_WIDTH = 16,
     parameter int NUM_KERNELS   = 1,
     parameter bit ENABLE_RELU   = 1'b0,
     parameter int FIFO_RAM_MODE = 0,      // 0 auto, 1 LUTRAM, 2 BRAM
     parameter int MAC_ARCH      = 0,      // 0 auto, 1 tree, 2 row chains, 3 single chain
     localparam int ACCUM_WIDTH  = 2*PIXEL_WIDTH + $clog2(WINDOW_SIZE**2)
  )(
     input  logic clk, rst_n,
     input  logic [PIXEL_WIDTH-1:0]        i_data,
     input  logic                          i_pixel_valid, i_weight_valid,
     input  logic [$clog2(NUM_KERNELS):0]  i_select_kernel,
     output logic signed [FEATURE_WIDTH-1:0] o_feature [NUM_KERNELS],
     output logic                          o_valid,
     output logic                          o_frame_done   // last feature of each frame
  );
     localparam int MAC_AUTO = (NUM_KERNELS == 1)
        ? ((WINDOW_SIZE <= CHAIN_MAX_N) ? 3 : ROW_OK ? 2 : 1)
        : ((ROW_OK && WINDOW_SIZE**2 * NUM_KERNELS <= ROW_CHAIN_MAX_DSP) ? 2 : 1);
  ```,
) <lst-top>

== Implementation Notes

- *Coding style.* SystemVerilog-2017, `always_ff` / `always_comb`, typed parameters and
  generate-selected architectures. Every stage uses an active-low asynchronous reset for control
  and valid bits, except the FIFO pointers and flags, whose synchronous clear is shared by `rst_n`
  and the frame end; datapath registers inside DSP slices and SRLs have no reset so they map onto
  the hardened primitives.
- *Inference attributes.* `srl_style = "srl"` (line buffer), `srl_style = "register"` (DSP skew),
  `use_dsp = "yes"`/`"no"` (multiplies vs. row-sum tree), `ram_style` via `FIFO_RAM_MODE`, and
  `max_fanout = 24` on the pixel write enable of the single-chain build. The routed netlist confirms
  AREG, BREG, MREG and PREG in all nine slices.
- *Elaboration-time decisions.* MAC architecture, clamp generation and FIFO memory type are
  `localparam` functions of the parameters, so each build contains only the logic it needs.
- *Continuous integration.* A GitHub Actions pipeline runs Verible style lint, Slang semantic
  analysis and Verilator synthesizability lint on every push to `hw/`. Locally, every RTL file
  compiles without warnings under QuestaSim lint (`vlog -lint -pedanticerrors`) and synthesizes
  with no critical warnings.

// =====================================================================
= Verification <sec-verif>
// =====================================================================

== Strategy

Correctness is established at three levels (@fig-verif-flow). A self-checking SystemVerilog
testbench with an internal model sweeps the parameter space. An independent Python golden model
drives the same RTL in QuestaSim through a file-based testbench and compares every feature. Finally,
the FPGA flow and the board wrapper are simulated before synthesis. No level trusts another: the
Python model was written separately from the RTL and from the SystemVerilog model.

#fig("figures/diagrams/verification_flow.png", [Verification flow: self-checking SystemVerilog testbench (left) and the Python golden model driving `conv_image_tb` in QuestaSim (right), with the pass counts of each suite.]) <fig-verif-flow>

== Golden Reference Model

`sw/conv_lab/core/reference.py` is a bit-accurate NumPy model of the datapath: valid
cross-correlation, round half up on DROP bits, and saturation to 16 bits. It shares no code with the
RTL. Its own unit tests check non-tie rounding, positive and negative ties, and every value a 3 × 3
accumulator can hold (2#super[20] values) against the definition of @eq-round.

#figure(
  caption: [Core of the golden model (`sw/conv_lab/core/reference.py`)],
  ```python
  def convolve(image, kernel, *, relu=False):
      mac = _valid_correlate(image, np.array(kernel.rows, dtype=np.int64))
      features = _round_saturate(mac, drop_bits(kernel.size))
      return apply_relu(features) if relu else features

  def _valid_correlate(image, weights):
      k, out = weights.shape[0], image.shape[0] - weights.shape[0] + 1
      acc = np.zeros((out, out), dtype=np.int64)
      for kr in range(k):
          for kc in range(k):
              acc += image[kr:kr + out, kc:kc + out].astype(np.int64) * weights[kr, kc]
      return acc

  def _round_saturate(values, drop):
      if drop > 0:
          quotient = values >> drop                    # floor
          remainder = values - (quotient << drop)
          values = quotient + (remainder >= 1 << (drop - 1))   # tie -> up
      return np.clip(values, -32768, 32767).astype(np.int32)
  ```,
) <lst-golden>

== Testbench Architecture

*`conv_system_tb` (self-checking, @fig-tb-structure).* Parameterized by `WINDOW_SIZE`, `INPUT_SIZE`, `NUM_KERNELS`,
`ENABLE_RELU` and `STALL`. It loads kernels, streams frames, captures every feature of every lane
and compares with its internal model (MAC → round half up → clamp → ReLU). Eleven tests run per
configuration. Seven directed single-frame tests cover identity, Laplacian, negative weights and
extreme pixel and weight values. Four frame-protocol tests follow: four frames back to back after
one reset, three frames with random idle gaps, three frames with a new kernel loaded between
frames, and a frame abandoned halfway and recovered by reset. `o_frame_done` is checked on every
cycle: high exactly on the last feature of each frame and never without `o_valid`. With `STALL = 1`
the pixel valid drops for random 1–3 cycle gaps and 20-cycle pauses; feature values, order and count
must not change.

#fig("figures/diagrams/tb_structure.png", [Structure of `conv_system_tb`. The test sequence drives the stimulus generators and drivers into the DUT; the reference model fills one expected-feature queue per lane, and the monitor compares every valid output and the frame-done pulse against it.], width: 90%) <fig-tb-structure>

*`conv_image_tb` + `conv_lab` (golden model).* The Python harness writes `stimulus.txt` (geometry,
kernels in hardware tap order, one or more frames of pixels), elaborates `conv_image_tb` for that
geometry with `-g` overrides, streams the frames after a single reset — back to back or with a
`+gap` — and parses `features.txt`. The testbench fails the run unless `o_frame_done` marks the last
feature of every frame. The harness computes the reference of each frame, compares them bit for bit
and renders `input | hardware | reference` images. The same harness backs an interactive CLI and
the pytest regression. @fig-conv-lab shows how the `conv_lab` package is layered: the front ends call
the harness, which is the only module where the reference side and the hardware side meet.

#fig("figures/verif/conv_lab_architecture.png", [Architecture of the `conv_lab` verification software (`sw/conv_lab`). Four layers, each importing only the layers below it; one run through the harness is numbered 1 to 5, and the file contract connects it to `conv_image_tb` in QuestaSim.]) <fig-conv-lab>

*Board wrapper testbench.* `conv_axi_lite_tb` drives the AXI4-Lite wrapper of the board demo exactly
like the PYNQ driver: one soft reset, five frames without a reset (three with new kernels), then a
frame after a second soft reset. It checks every feature read back through AXI and the per-frame
counters, including `FRAME_COUNT`, which counts `o_frame_done` pulses.

== Test Cases <sec-test-cases>

#figure(
  caption: [Hardware regression cases (`sw/tests/regression`, QuestaSim, Python golden model)],
  table(
    columns: (1.25fr, auto, 2fr),
    table.header[Case][Frames][Purpose],
    [Every preset on every pattern], [5], [All 12 preset kernels as parallel lanes on ramp, checker, circle, bars and noise],
    [Frame size], [10], [4×4 (smallest, FIFO depth 2), 16/17 and 32/33 (counter width steps), odd sizes, 64×64],
    [Every tap position], [2], [Nine one-hot kernels at +16 and −128: any tap-order or row-swap bug shifts a lane],
    [Extreme pixels and weights], [4], [Black, white, pixel checker and noise against all +127, all −128, alternating: largest positive and negative sums, sign flips every pixel],
    [Round-half-up ties], [1], [Every pixel 0..255 through centre taps ±1, ±3, ±7: all positive and negative .5 ties],
    [Lane count], [9], [`NUM_KERNELS` 1–16 across the select-bus width steps],
    [Window size], [2], [5 × 5 and 7 × 7 (row-chain MAC)],
    [Randomized], [20], [Random size, image, window (3 or 5) and 1–6 random kernels],
    [Streams without reset], [8], [Several frames in one simulation after one reset, each frame checked on its own: the five patterns back to back and 5 cycles apart, 5 × 5 and 7 × 7 row chains, four random streams (2–4 frames, gap 0, 1 or 17 cycles)],
    [*Total*], [*61*], [#val(verif.cases) features compared, #verif.mismatches mismatches],
  ),
) <tab-tests>

#figure(
  caption: [Configuration sweeps of the self-checking testbench and other checks],
  table(
    columns: (1.6fr, 2fr, auto),
    table.header[Run][Space][Result],
    [`conv_system_tb`, final RTL], [40 configurations: N = 2–11, W = 4–64 (including 4, 5, 6, 8, 12, 13, 17 and 33), K = 1–16, ReLU, stall, all three MACs; 11 tests each, 4 of them multi-frame without reset], [40 / 40],
    [`conv_system_tb`, per architecture], [3×3 K=1 (chain); 5×5 K=2 ReLU stall (rows); 11×11 K=1 (tree)], [3 / 3],
    [`conv_system_tb`, component architectures], [Tree: 84 + 40 stalled; row chains: 168; single chain: 40], [all pass],
    [MAC selection], [23 (N, K) elaborations, printed `MAC_SEL` checked against @tab-macsel], [23 / 23],
    [Golden-model unit tests], [Model, rounding ties, 2#super[20] rounding sweep, single- and multi-frame file contract, CLI, architecture rules], [94 / 94],
    [Output FIFO unit test], [Two frames after one reset: prefill, order, `o_last` on the last entry, re-arm], [pass],
    [Line buffer unit test], [Three frames with random stalls, no reset: `row_done`, `rows_ready` refill, `o_frame_end`, row taps; 8 × 8 / 3 rows and 13 × 13 / 5 rows], [pass],
    [Kernel register unit test], [Load in bursts, reload without reset, over-long load, hold, reset], [7 / 7],
    [PYNQ driver host test], [`conv_demo.py` against a register-level model of `conv_axi_lite`: one reset, kernel written only when changed, frames without reset, tap order, two lanes with ReLU], [4 / 4],
    [Mutation check], [Three deliberate bugs: FIFO never re-arms (caught by the FIFO assertion), sticky `rows_ready` (3 stream tests fail), `o_frame_done` never raised (11 of 11 tests fail)], [3 / 3 caught],
    [Board AXI wrapper (`board_sim`)], [3×3/32 K=1, 3×3/32 K=2, 5×5/16 ReLU; five frames without reset (new kernels between frames) and one after a soft reset; identity, Sobel, extremes, random], [all features bit-exact],
    [Round/saturate exhaustive], [All 2#super[20] inputs, valid held and random gaps, IN/OUT 20/16, 17/16, 16/16, 12/16], [pass],
  ),
) <tab-sweeps>

== Results: Hardware versus Golden Model

#key-result[All 61 regression cases (8 of them multi-frame streams without reset), all 40 sweep
configurations with their frame-protocol tests and every image run matched the golden model bit for
bit: #verif.mismatches mismatching output features, and `o_frame_done` on the last feature of every
frame.]

@fig-cli-circle shows the output of the verification software on a 32 × 32 circle for five kernels
evaluated in parallel lanes of one simulation; each hardware column carries its verdict and is drawn
on the reference's grey scale, so a wrong hardware value would clip to black or white.
@fig-cli-inspection applies Sobel-X, Sobel-Y and Laplacian to a 128 × 128 synthetic
industrial-inspection image (a machined plate with bolt holes, a slot, a hairline crack and a small
void): 47 628 features, all identical. @fig-cli-relu shows the ReLU path; the verdict is always
taken on the raw signed features, so a clamp cannot hide a sign error.

#fig("figures/verif/cli_circle.png", [Verification software output: 32 × 32 circle, five kernels (Sobel-X, Sobel-Y, Laplacian, Gaussian, sharpen) as parallel lanes. Columns: input, hardware output with verdict, golden-model output.], width: 58%) <fig-cli-circle>

#fig("figures/verif/cli_inspection.png", [128 × 128 inspection image through Sobel-X, Sobel-Y and Laplacian: RTL in QuestaSim (middle) and golden model (right), all 47 628 features bit-exact. The crack and void stand out in every edge map.], width: 82%) <fig-cli-inspection>

#fig("figures/verif/cli_checker_relu.png", [Checkerboard through Sobel-X and Laplacian with ReLU applied to the displayed output; verdicts on raw features.], width: 56%) <fig-cli-relu>

#fig("figures/verif/regression_presets.png", [Hardware regression image of the case "every preset on the checker pattern": twelve preset kernels run as parallel lanes of one frame; the first four lanes are shown, every lane MATCH (all 61 cases in `figures/verif/regression_summary.txt`).], width: 60%) <fig-regression>

@tab-samples lists expected and hardware values side by side. The first six rows are the largest
positive and negative feature of each kernel on the inspection image, read from the golden and
hardware output files in `figures/verif/` (row and column of the output map, 0-based); the input
window is the 3 × 3 patch of the image under the kernel. The weighted sum is divided by
2#super[4] = 16 with round half up: for example 448 / 16 = 28.0 and −464 / 16 = −29.0. The last two
rows are the extreme-value regression case, where a white frame meets all-+127 and all-−128 kernels
and produces the largest possible magnitudes of the 3 × 3 build; the regression reported MATCH for
every feature of those frames.

// 3 × 3 input window: one monospace line per row, numbers padded with hidden digits so columns align.
#let win(..rows) = text(size: 0.85em, stack(spacing: 4pt, ..rows.pos().map(r => r
  .split(" ").filter(s => s != "")
  .map(s => [#hide(raw("0" * (3 - s.len())))#raw(s)])
  .join(raw(" ")))))

#figure(
  caption: [Expected (golden model) versus hardware (RTL in QuestaSim) output values],
  table(
    columns: (auto, auto, auto, auto, auto, auto, auto),
    align: (left + horizon, center + horizon, center + horizon, right + horizon, right + horizon, right + horizon, center + horizon),
    table.header[Kernel][Output (r, c)][Input window][Weighted sum][Expected][Hardware][Match],
    [Sobel-X], [(27, 18)], win("168 134  57", "157  71  41", "151  51  46"), [448], [28], [28], [✓],
    [Sobel-X], [(95, 32)], win(" 56 143 168", " 38  69 158", " 40  63 152"), [−464], [−29], [−29], [✓],
    [Sobel-Y], [(89, 25)], win("175 173 170", "145 151 147", " 62  56  61"), [456], [29], [29], [✓],
    [Sobel-Y], [(36, 23)], win(" 54  42  46", "135  75  54", "165 158 149"), [−446], [−28], [−28], [✓],
    [Laplacian], [(32, 94)], win("155  67  44", "166 140  55", "167 152  70"), [120], [8], [8], [✓],
    [Laplacian], [(23, 97)], win("168 155 133", "141  66  60", " 69  46  44"), [−138], [−9], [−9], [✓],
    [All +127], [any], [all 255], [291 465], [18 217], [18 217], [✓],
    [All −128], [any], [all 255], [−293 760], [−18 360], [−18 360], [✓],
    table.cell(colspan: 7, align: left)[*Inspection image:* 3 kernels × 126 × 126 = 47 628 features, 0 mismatches. *All regression cases:* #val(verif.cases) features, #verif.mismatches mismatches.],
  ),
) <tab-samples>

== Waveforms

The waveforms below were recorded from `conv_image_tb` in QuestaSim (VCD) for two 8 × 8 frames
streamed back to back after a single reset — a vertical edge and its mirror image — through the
Sobel-X kernel, using the competition datapath (3 × 3, single cascade). A small frame keeps every
phase visible: the kernel load, the line-buffer fill, the first valid window, the eleven-cycle DSP
cascade, the two-cycle rounding stage, the FIFO prefill, the continuous output and the boundary
between the two frames. The second frame behaves exactly like the first: 46 cycles from its first
pixel to its first feature and 81 to its last, in both frames. The frame-end mark reaches the FIFO
13 cycles after the last window, and `o_frame_done` follows three cycles later, when the FIFO has
drained.

#fig("figures/waves/wave_start.png", [Waveform (a): weights shift in, pixels fill the line buffer, `window_valid` rises on the first complete window and the cascade sum appears 11 cycles later.]) <fig-wave-start>

#fig("figures/waves/wave_output.png", [Waveform (b): rounded features enter the FIFO with row-edge gaps; after the prefill `o_valid` stays high and one feature leaves per clock cycle.]) <fig-wave-output>

#fig("figures/waves/wave_frames.png", [Waveform (c): the frame boundary without a reset. `i_pixel_valid` never drops between the frames; the row ring's last-row bit covers the last row and `rows_ready` falls, the frame-end mark reaches the FIFO with frame 1's last feature, which carries `o_frame_done`; the registered clear drops `q_prefilled` one cycle later, and frame 2 then prefills and streams exactly like frame 1.]) <fig-wave-frames>

// =====================================================================
= FPGA Implementation Results <sec-fpga>
// =====================================================================

== Target Device and Tool Flow

The design targets the AMD Zynq-7020 `xc7z020clg400-1` of the PYNQ-Z2 board with Vivado 2018.2.
The repository's `fpga/` flow runs in batch mode from the same RTL file list as the simulators:
non-project synthesis (`synth_design`, default strategy), then `opt_design`, `place_design`,
`phys_opt_design` and `route_design` with a single 4.000 ns clock constraint on `clk`. Reports are
written for synthesis and for the routed design; power is computed on the routed checkpoint with a
SAIF recorded by xsim for each benchmark (@sec-power).

== Resource Utilization

#figure(
  caption: [Post-route resource utilization, competition build],
  table(
    columns: (1.4fr, 1fr, 1fr, 1fr),
    align: (left, right, right, right),
    table.header[Resource][Used][Available][Utilization],
    [LUTs (logic 37, LUTRAM 24, SRL 17)], [#fpga.luts], [#fpga.luts-avail], [#pct(fpga.luts, fpga.luts-avail)],
    [Flip-flops], [#fpga.ffs], [#fpga.ffs-avail], [#pct(fpga.ffs, fpga.ffs-avail)],
    [DSP48E1], [#fpga.dsps], [#fpga.dsps-avail], [#pct(fpga.dsps, fpga.dsps-avail)],
    [Block RAM tiles], [#fpga.brams], [#fpga.brams-avail], [#pct(fpga.brams, fpga.brams-avail)],
    [*LUT + 50 · DSP + 100 · BRAM*], [*#weighted-area*], [], [],
  ),
) <tab-util>

Half of the LUTs are memory (the SRL line buffer and the LUTRAM FIFO); the whole arithmetic datapath
from the window to the rounded feature uses 8 LUTs. The 521 flip-flops are dominated by the window
(75), the kernel register (76) and the cascade skew registers (226); the frame protocol adds the
32-bit one-hot row ring and the 13-stage frame-end delay line. None of them enter the FoM.

== Timing

#figure(
  caption: [Post-route timing summary],
  table(
    columns: (1.5fr, 1fr),
    align: (left, right),
    table.header[Metric][Value],
    [Target clock period], [#fix(perf.clock-target) ns (250 MHz)],
    [Worst negative slack (WNS)], [+#fix(perf.wns) ns],
    [Total negative slack (TNS)], [#fix(perf.tns) ns],
    [Worst hold slack (WHS)], [+#fix(perf.whs) ns],
    [Maximum frequency], [#perf.fmax MHz],
    [Timing met], [#perf.timing-met — 0 failing endpoints],
  ),
) <tab-timing>

$ f_"max" = 1 / (T_"clk" - "WNS") = 1 / (4.000 - 0.728) " ns" = 305.6 " MHz" $ <eq-fmax>

*Critical path.* The worst path is not in the arithmetic: it runs inside `output_fifo` from the read
pointer (`q_read_ptr[0]`) through the empty comparator (LUT6, LUT3) to the clock enable of the 16
output data registers — 3.007 ns, 2 logic levels, 77 % routing. Every DSP-to-DSP path uses the dedicated PCOUT→PCIN
cascade (0.48 ns) and every skew register drives a slice input directly. An earlier timing sweep
of the cascade closed 300 MHz with +0.627 ns slack (369 MHz), so Fmax is limited by fabric control
routing, not by the datapath.

== Power <sec-power>

Vivado's vectorless estimate assumes a 12.5 % toggle rate on every net and reports low confidence;
for image data it is pessimistic. `fpga/sim/conv_system_power_tb.sv` therefore streams one full
32 × 32 frame at one pixel per cycle with no stalls (the sustained worst case) while xsim records
the switching activity of the whole design at 250 MHz; the SAIF is annotated on the routed
checkpoint. Two workloads are reported.

#figure(
  caption: [Total on-chip power of the routed competition build (Vivado `report_power`)],
  table(
    columns: (1.5fr, auto, auto, auto, auto),
    align: (left, right, right, right, right),
    table.header[Workload][Total][Dynamic][Device static][Confidence],
    [Bars (4 px) + Sobel-X], [#fix(perf.power-total * 1000) mW], [#fix(perf.power-dynamic * 1000) mW], [#fix(perf.power-static * 1000) mW], [SAIF],
    [Pixel checkerboard + Sobel-Y], [#fix(perf.power-total-checker * 1000) mW], [#fix(perf.power-dynamic-checker * 1000) mW], [#fix(perf.power-static-checker * 1000) mW], [SAIF],
    [Vivado vectorless (reference)], [#fix(perf.power-vectorless * 1000) mW], [54.699 mW], [105.161 mW], [Low],
  ),
) <tab-power>

#fig("figures/charts/power_breakdown.png", [Power breakdown of the routed design on both workloads (mW).]) <fig-power>

Device static power is 87 % of the total. 76 mW of it belongs to the idle Zynq processing system
and its XADC rails, identical for every PYNQ-Z2 design and unaffected by the RTL; the programmable
logic leaks about 29 mW. Of the 15.3 mW dynamic power with bars + Sobel-X, 9.3 mW is the 16 toggling
output pins and 5.1 mW the clock network; logic, signals and DSPs together draw under 1 mW. With the
checkerboard + Sobel-Y workload the input toggles maximally, but on a one-pixel checkerboard rows r
and r + 2 are identical, so Sobel-Y is exactly zero everywhere: the outputs never move and the I/O
power vanishes. Only 7 % of design nets match the SAIF by name, because registers absorbed into
DSP slices lose their RTL names; Vivado propagates the remaining activity.

// =====================================================================
= Performance and Figure of Merit <sec-perf>
// =====================================================================

== Latency and Throughput

#figure(
  caption: [Latency budget of one pixel (competition build)],
  table(
    columns: (1.4fr, auto, 2fr),
    align: (left, center, left),
    table.header[Stage][Cycles][Note],
    [Input registers], [1], [`r_data`, pixel and weight write enables],
    [Line buffer], [0], [SRL tap read combinationally into the window],
    [Window generator], [1], [Registered window and `window_valid`],
    [MAC: single DSP cascade], [11], [2 + N²: input skew, MREG and nine PREGs],
    [Round and saturate], [2], [Guard-bit split, round-half-up adder],
    [ReLU], [0], [Bypassed (1 when enabled)],
    [Output FIFO], [1], [Registered read; prefill adds the frame warm-up below],
    [*Pixel pipeline depth*], [*#design.pipeline-stages*], [],
  ),
) <tab-latency>

A frame additionally needs N − 1 rows and N − 1 pixels before the first window exists, and the FIFO
waits for 58 features before it starts reading. Measured in QuestaSim on the 32 × 32 frame, the
first feature leaves #val(perf.latency) cycles after the first pixel and the last one
#val(perf.frame-cycles) cycles after it. In steady state the design emits *one output pixel per
clock cycle*: 900 features in 900 consecutive cycles with no gaps, so the throughput is 1.0 output
pixel per cycle, or 250 Mpx/s at the 250 MHz constraint (305.6 Mpx/s at Fmax). The second and
every later frame of a stream behave identically, without a reset (@fig-wave-frames).

== Figure of Merit

$ "FoM" = "Throughput" / ("Power" times ("LUTs" + 50 times "DSPs" + 100 times "BRAMs")) $ <eq-fom>

#figure(
  caption: [Figure of Merit of the competition build],
  table(
    columns: (1.6fr, 1fr, 1fr, 1fr),
    align: (left, right, right, right),
    table.header[Quantity][Bars + Sobel-X][Checker + Sobel-Y][Vectorless],
    [Throughput (px / cycle)], [1], [1], [1],
    [Power (W)], [#fix(perf.power-total, digits: 6)], [#fix(perf.power-total-checker, digits: 6)], [#fix(perf.power-vectorless, digits: 6)],
    [LUTs], [#fpga.luts], [#fpga.luts], [#fpga.luts],
    [DSPs × 50], [#(50 * fpga.dsps)], [#(50 * fpga.dsps)], [#(50 * fpga.dsps)],
    [BRAMs × 100], [#(100 * fpga.brams)], [#(100 * fpga.brams)], [#(100 * fpga.brams)],
    [Weighted area], [#weighted-area], [#weighted-area], [#weighted-area],
    [*FoM*], [*#fix(fom, digits: 5)*], [*#fix(fom-checker, digits: 5)*], [#fix(fom-vectorless, digits: 5)],
  ),
) <tab-fom>

*Cost of continuous streaming.* The same flow on the single-frame build (reset between frames)
gave 71 LUTs, 474 FFs, +0.794 ns and FoM 0.01596 / 0.01730. Streaming frames without a reset adds
7 LUTs (+1.3 % weighted area) and −1.1 % FoM: the one-hot row ring and the frame-end delay line are
flip-flops only, and the FIFO's frame re-arm costs 6 LUTs. A first version that merged the re-arm into
the pointer logic cost 22 LUTs and slack; @sec-datapath describes the cheaper structure.

== Operating Frequency and Energy per Pixel

Because throughput is counted per *cycle*, the FoM numerator does not change with the clock rate
while dynamic power grows with it. On a row-chain build implemented at three constraints with a SAIF
recorded at each period, the FoM rose from 0.01284 at 250 MHz to 0.01424 at 150 MHz, yet energy per
output pixel moved the other way, from 0.79 nJ to 0.52 nJ, because the static floor is shared by
more pixels per second (@fig-freq). We report 250 MHz: it is the best real performance, the lowest
energy per pixel and the honest basis for Fmax.

#fig("figures/charts/frequency_tradeoff.png", [FoM and energy per output pixel versus clock frequency (row-chain build, SAIF at each period).], width: 55%) <fig-freq>

// =====================================================================
= Bonus Features <sec-bonus>
// =====================================================================

#figure(
  caption: [Optional bonus features],
  table(
    columns: (1.3fr, auto, 2fr),
    table.header[Feature][Status][Evidence],
    [ReLU activation], status("done"), [`relu_unit` per lane (@sec-relu); verified in the sweeps with ReLU on, in `board_sim` and in @fig-cli-relu],
    [One output pixel per cycle], status("done"), [Prefill FIFO; 900 features in 900 consecutive cycles, @sec-perf, @fig-wave-output],
    [Multiple kernels], status("done"), [`NUM_KERNELS` lanes sharing one window; 1–16 kernels verified bit-exact (@tab-tests)],
    [FPGA board demonstration], status("done"), [PYNQ-Z2 overlay built and simulated end to end (@sec-board)],
    [Edge-detection / inspection demo], status("done"), [Sobel and Laplacian on the inspection image (@fig-cli-inspection) and on the board],
  ),
) <tab-bonus>

== Multiple Kernels

All K lanes share the input registers, line buffer and window, so the window is computed once and
presented to every lane on the same cycle; each lane adds a kernel register, a MAC, rounding, optional
ReLU and a FIFO. The MAC selection switches to row chains for K ≥ 2 because a single cascade per
lane would repeat its N⁴ skew registers. The hardware regression evaluates all twelve preset kernels
as parallel lanes of one frame (@fig-regression), so twelve kernels cost one frame of simulated time.

== Board Demonstration (PYNQ-Z2) <sec-board>

The overlay wraps `conv_system` in an AXI4-Lite peripheral, `conv_axi_lite`, attached to the Zynq
processing system (@fig-board). The ARM core writes the kernel and the pixels as register writes
(four pixels per write); the wrapper feeds them to the accelerator one per clock cycle and stores every
output feature in a block-RAM result memory that Python reads back. The accelerator is reset once
when the overlay is opened; after that every frame streams without a reset. `o_frame_done` sets the
frame-done status bit and increments `FRAME_COUNT`, the next frame's first pixel clears the per-frame
counters, and the driver rewrites a kernel only when it changes. Status registers report the
weight, pixel, feature and frame counts and the in-fabric latency; four LEDs show weights loaded,
streaming, frame done and a heartbeat.

#fig("figures/diagrams/board_demo.png", [Board demonstration on the PYNQ-Z2. The Python driver on the ARM cores reaches `conv_axi_lite` through AXI GP0 and the interconnect; the host PC runs the notebook over Ethernet. After the overlay is loaded, steps 2 to 6 repeat for every frame without a reset (the kernel is rewritten only when it changes).]) <fig-board>

#figure(
  caption: [Board demonstration build (`fpga/bitstream`, Vivado 2018.2)],
  table(
    columns: (1.4fr, 2fr),
    table.header[Item][Value],
    [Overlay files], [`conv_demo.bit`, `conv_demo.hwh` (PYNQ overlay pair)],
    [Resources (whole overlay)], [813 LUT, 9 DSP, 0.5 BRAM tile (AXI interconnect, wrapper, result memory, accelerator)],
    [Timing], [100 MHz fabric clock, WNS +2.560 ns],
    [Address map], [`M_AXI` at 0x43C00000–0x43CFFFFF],
    [Host software], [`conv_demo.py` (driver, golden model, CLI) and `conv_demo.ipynb`],
    [Pre-silicon check], [`conv_axi_lite_tb`: every feature of three builds bit-exact through AXI, five frames without reset and one after a soft reset; the Python driver tested against a register-level model of the wrapper (`fpga/board/tests`)],
  ),
) <tab-board>

`conv_demo.py` loads the overlay, runs the demo kernels on synthetic patterns or on any picture
resized to the overlay size, compares every frame with a copy of the golden model and saves an image
grid. That model was checked against `reference.py` on 135 frames. The same flow is available as a
Jupyter notebook that also combines the Sobel-X and Sobel-Y frames computed on the FPGA into an edge
magnitude image.

// =====================================================================
= Design Space Exploration and Trade-offs <sec-tradeoffs>
// =====================================================================

== Exploration Path

Starting from a textbook design (parallel DSP multipliers and a fabric adder tree), we built and
measured every candidate on the same device, constraint and SAIF methodology before changing the
design (@fig-explore, @tab-explore). All variants were verified against the golden-model
testbench before measurement.

#fig("figures/charts/exploration_fom.png", [FoM of the explored approaches on the same natural-image SAIF at 250 MHz (resource points in brackets). Grey: baseline; red: rejected DSP-saving schemes; blue and navy: the DSP-cascade path.]) <fig-explore>

#figure(
  caption: [Design-space exploration, xc7z020, 250 MHz, K = 1, natural-image SAIF],
  table(
    columns: (1.9fr, auto, auto, auto, auto, auto, auto),
    align: (left, right, right, right, right, right, right),
    table.header[Approach][LUT][FF][DSP][WNS (ns)][Power (W)][FoM],
    [Baseline: multipliers + adder tree], [243], [442], [9], [+0.627], [0.136], [0.01061],
    [+ clock-enable gating], [242], [441], [9], [+0.530], [0.136], [0.01063],
    [DSP post-adder row chains], [149], [335], [9], [+0.492], [0.130], [0.01284],
    [+ round/saturate split], [140], [353], [9], [+0.921], [0.129], [0.01314],
    [+ bit-growing row tree], [137], [350], [9], [+0.760], [0.129], [0.01321],
    [Single 9-DSP cascade], [68], [456], [9], [+0.925], [0.127], [0.01520],
    [Double MAC (two products per DSP)], [429], [919], [5], [+0.563], [0.144], [0.01023],
    [DSP multi-pumping ×3], [262], [380], [3], [+0.008], [—], [0.00503],
    [Fabric multipliers, no DSP], [933], [—], [0], [−1.483], [—], [fails timing],
  ),
) <tab-explore>

== Rejected Alternatives

- *Fabric multipliers.* 933 LUTs and −1.48 ns: an 8 × 8 multiply costs about 87 LUTs, more than
  the 50 a DSP is worth.
- *Time-multiplexing DSPs.* Sharing a slice across taps divides throughput by the sharing factor
  while 81 % of the power is static and does not shrink, so every factor loses (×2: 0.88×, ×9: 0.40×).
- *DSP multi-pumping* (three slices clocked three times per step). 3 DSPs and 412 points, but one
  output every three clock cycles: FoM 0.00503 per clock cycle.
- *Double MAC* (two products per DSP, Lee et al.). Packing needs a shared operand; with one kernel
  that forces pixel pairs from adjacent windows, 2:1 multiplexers, correction adders and a
  serializer. It saved 4 DSPs (200 points) and paid 280 LUTs: 20 % worse.
- *Clock-enable gating* of the DSP and tree registers is bit-exact and free in area, but under
  sustained streaming the enables never gate anything; power was identical and slack dropped.
- *LUTRAM ring line buffer.* Fewer LUTs, more power; FoM within ±0.5 % (@sec-memory).

== Three MAC Architectures at the Competition Point

#fig("figures/charts/architectures_3x3.png", [Fabric resources and FoM of the three MAC architectures at 3 × 3, 32 × 32, one kernel, 250 MHz (same flow and benchmarks).]) <fig-arch3>

#figure(
  caption: [The three MAC architectures, competition configuration, measured on the single-frame builds before the frame protocol was added (+7 LUTs for every architecture, @tab-fom)],
  table(
    columns: (1.4fr, 1fr, 1fr, 1fr),
    align: (left, right, right, right),
    table.header[][Tree][Row chains][*Single cascade*],
    [LUT / FF / DSP / BRAM], [205 / 429 / 9 / 0], [110 / 322 / 9 / 0], [*70 / 474 / 9 / 0*],
    [LUTs inside the MAC], [143], [43], [*2*],
    [Weighted area], [655], [560], [*520*],
    [WNS / Fmax], [+0.751 / 307.8 MHz], [+0.543 / 289.3 MHz], [*+0.757 / 308.4 MHz*],
    [Bars + Sobel-X: power / FoM], [124.6 mW / 0.01226], [120.4 mW / 0.01483], [*120.4 mW / 0.01597*],
    [Checker + Sobel-Y: power / FoM], [124.4 mW / 0.01227], [110.8 mW / 0.01612], [*111.1 mW / 0.01731*],
  ),
) <tab-arch3>

== Scaling with Kernel Size <sec-scaling>

#fig("figures/charts/scaling_kernel_size.png", [Flip-flops (log scale) and slack of the three architectures versus kernel size, one kernel, 250 MHz; shaded bands show the automatic selection.]) <fig-scaling>

The single cascade wins at 3 × 3 because its extra 243 flip-flops over the row chains are free in the
FoM and cost no measurable power. At 5 × 5 its skew registers grow to 2742 FFs (+2250) and cost about
20 mW, and at 9 × 9 the 26 775 FFs and the long DSP column miss timing by 1.38 ns; 13 × 13 does not
fit the device. The row chains grow as N³ and close 250 MHz up to 9 × 9. The tree has no skew at all
and keeps positive slack to 13 × 13, and only it can map multipliers into fabric once the 220 DSPs
are exhausted (17 × 17 built with 200 DSPs plus fabric multipliers). This is exactly the selection
rule of @tab-macsel.

== Other Trade-offs

#figure(
  caption: [Design trade-offs and choices],
  table(
    columns: (0.9fr, 1.1fr, 1.1fr, 1.6fr),
    table.header[Decision][Option A][Option B][Choice and rationale],
    [MAC structure], [N² parallel multipliers], [Time-multiplexed MAC], [Parallel DSPs: time-multiplexing cuts throughput faster than power or area],
    [Additions], [Fabric adder tree], [DSP post-adders (cascade)], [Cascade: 143 → 2 MAC LUTs; FFs for skew are free in the FoM],
    [Multipliers], [DSP48E1], [LUT-based], [DSP: 50 points versus about 87 LUTs, and timing closes],
    [Line buffer], [BRAM], [SRL / LUTRAM ring], [SRL: 22 LUTs, no BRAM (100 points), lowest power],
    [Output FIFO memory], [BRAM], [LUTRAM], [Chosen per build by FoM cost; LUTRAM at 32 × 32, BRAM wins at 64-pixel rows (+4 to +7 %)],
    [Pipelining], [Deep (high Fmax)], [Shallow (low latency)], [Register every DSP stage (AREG/BREG/MREG/PREG): throughput is per cycle, latency is only 16 stages],
    [Rounding], [Truncation / half even], [Round half up], [Half up: unbiased except ties, one incrementer, no sticky logic],
    [Overflow], [Always clamp], [Clamp when reachable], [Proven unreachable for 8-bit data; logic generated only if widths change],
    [Throughput], [Gapped output], [Prefill FIFO], [FIFO: one pixel per cycle (bonus) for 43 LUTs including the frame re-arm],
    [Frames], [Reset between frames], [Frame-end mark, no reset], [No reset: 7 LUTs (−1.1 % FoM) for continuous video; counters as a one-hot ring and a flip-flop delay line],
  ),
) <tab-tradeoffs>

== Discussion and Limitations

- *Power is dominated by the device.* 87 % of the reported power is static and 63 % of it belongs to
  the idle processing system, so beyond a point LUT savings raise the FoM mainly through the area
  term. A pure-PL power figure would be about 15 mW dynamic plus 29 mW PL leakage.
- *SAIF matching.* With the arithmetic inside DSP slices only 7 % of nets match the SAIF by name;
  the vectorless estimate ranks all our builds in the same order, which we used as a cross-check.
- *Frame protocol.* Frames stream without a reset, but the interface has no start-of-frame input:
  the accelerator counts pixels to find frame boundaries. A host that abandons a frame partway must
  therefore reset before the next one (verified by the abort test).
- *Very small images.* The FIFO prefill threshold is capped at the frame's feature count, so frames
  smaller than their row-edge gap count (7 × 7 on 8 × 8, 9 × 9 on 12 × 12, 11 × 11 on 13 × 13 in our
  sweeps) still drain, one feature per cycle, because the whole frame is buffered before the first
  read.

// =====================================================================
= Conclusion and Future Work <sec-conclusion>
// =====================================================================

ARA Silicon's accelerator meets every mandatory specification and implements all five bonus items.
Its central result is that, for streaming CNN convolution on a DSP-rich FPGA, *all* arithmetic can
live in the DSP48E1 slices: a single PCOUT→PCIN cascade computes a 3 × 3 window sum with 2 LUTs,
bringing the complete 32 × 32 accelerator to #fpga.luts LUTs, 9 DSPs and no BRAM at #perf.fmax MHz, one
output pixel per clock cycle and a Figure of Merit of #fix(fom, digits: 5) (bars + Sobel-X) and
#fix(fom-checker, digits: 5) (checkerboard + Sobel-Y), while streaming frames back to back without
a reset. Because the best structure depends on the
kernel, the same RTL selects between the cascade, row chains and an adder tree from N and K, and a
two-level verification flow proves every build bit-exact against an independent Python model.

Future work:

- Support multi-channel inputs and padding ("same" convolution) for complete CNN layers.
- Fold the rounding constant into the head DSP's C port (measured in an exploration build at
  FoM 0.01609 / 0.01755) once the generic clamp is not needed.
- A start-of-frame input (as AXI4-Stream `tuser`) so that a partial frame can be dropped without a
  reset.
- Evaluate Double-MAC packing for K ≥ 2, where two weights can share one pixel operand.
- Run the board demonstration on camera input and port the datapath to an ASIC flow.

// =====================================================================
#heading(numbering: none)[References]
// =====================================================================

#[
  #set enum(numbering: "[1]")
  + IEEE SSCS Egypt Chapter, "2026 Student Design Competition Announcement," 2026.
  + V. Sze, Y.-H. Chen, T.-J. Yang and J. S. Emer, "Efficient Processing of Deep Neural Networks:
    A Tutorial and Survey," _Proc. IEEE_, vol. 105, no. 12, pp. 2295–2329, 2017.
  + Xilinx, "7 Series DSP48E1 Slice User Guide," UG479, 2018.
  + Xilinx, "Vivado Design Suite User Guide: Power Analysis and Optimization," UG907, 2018.
  + S. Lee, D. Kim, D. Nguyen and J. Lee, "Double MAC on a DSP: Boosting the Performance of
    Convolutional Neural Networks on FPGAs," _IEEE Trans. Computer-Aided Design_, 2018.
  + B. Jacob et al., "Quantization and Training of Neural Networks for Efficient
    Integer-Arithmetic-Only Inference," _Proc. CVPR_, 2018.
  + AMD Xilinx, "PYNQ: Python Productivity for Zynq," documentation, 2018–2026.
  + Xilinx, "Virtex-6 FPGA DSP48E1 Slice User Guide," UG369, 2011.
]

// =====================================================================
#show: appendix
// =====================================================================

= Submission Package <app-package>

#figure(
  caption: [Deliverables and their location in the repository],
  table(
    columns: (1.3fr, 1.8fr, auto),
    table.header[Deliverable][Location][Status],
    [Report (this document)], [`docs/report/`], status("done"),
    [RTL source files], [`hw/ip/*/src/rtl/`, `hw/system/conv_system/src/rtl/`], status("done"),
    [Testbenches], [`hw/system/conv_system/src/tb/`, `fpga/board/tb/`], status("done"),
    [Golden model and regression], [`sw/conv_lab/`, `sw/tests/`], status("done"),
    [Input test images], [`docs/report/figures/inputs/`, generated patterns in `sw/conv_lab/core/images.py`], status("done"),
    [Expected and hardware output files], [`docs/report/figures/verif/*.csv` (golden and hardware per kernel)], status("done"),
    [FPGA reports (utilization / timing / power)], [`fpga/synth/default/`, `fpga/impl/default/`, `fpga/reports/default/`], status("done"),
    [Board overlay], [`fpga/bitstream/`, `fpga/board/`], status("done"),
    [Architecture exploration builds], [`experiments/`], status("done"),
  ),
) <tab-package>

= Reproducing the Results <app-repro>

#figure(
  caption: [Commands],
  ```bash
  # golden model unit tests and the hardware regression (QuestaSim on PATH)
  cd sw && python -m pytest -m "not hardware" && python -m pytest -m hardware
  # image comparison, e.g. the inspection demo
  python -m conv_lab --image ../docs/report/figures/inputs/inspection_plate.png \
         --size 128 --kernel sobel_x --kernel sobel_y --kernel laplacian --png out.png
  # FPGA: synthesis, implementation, benchmark power and FoM, PYNQ-Z2 overlay
  .\fpga\run.ps1                                     # Windows
  make fpga                                          # Linux
  # board wrapper test (xsim) and PYNQ driver test (no board)
  .\fpga\run.ps1 -Steps board_sim
  python -m pytest fpga/board/tests
  ```,
)

= Report Excerpts <app-extra>

#figure(
  caption: [Routed utilization by module (`fpga/impl/default/utilization_hier.txt`)],
  table(
    columns: (1.6fr, auto, auto, auto, auto, auto, auto),
    align: (left, right, right, right, right, right, right),
    table.header[Instance][Total LUTs][Logic LUTs][LUTRAM][SRL][FFs][DSP48],
    [`conv_system` (top)], [78], [37], [24], [17], [521], [9],
    [`gen_kerenl_register[0].u_kernel_register`], [5], [5], [0], [0], [76], [0],
    [`gen_mac[0].gen_single_chain.u_mac`], [2], [1], [0], [1], [226], [9],
    [`gen_output_fifo[0].u_output_fifo`], [43], [19], [24], [0], [32], [0],
    [`gen_round_sat[0].u_round_saturate`], [3], [3], [0], [0], [35], [0],
    [`u_line_buffer`], [22], [6], [0], [16], [39], [0],
    [`u_window_generator`], [3], [3], [0], [0], [75], [0],
  ),
)

#figure(
  caption: [Worst setup path (`fpga/impl/default/timing_summary.txt`)],
  ```text
  Slack (MET) :        0.728ns  (required time - arrival time)
    Source:            gen_output_fifo[0].u_output_fifo/q_read_ptr_reg[0]/C
    Destination:       gen_output_fifo[0].u_output_fifo/gen_lutram.o_data_reg[15]/CE
    Data Path Delay:   3.007ns  (logic 0.704ns (23.412%)  route 2.303ns (76.588%))
    Logic Levels:      2  (LUT3=1 LUT6=1)
  ```,
)
