// =====================================================================
//  Design data - single source of truth for the report.
//  Numbers come from fpga/reports/default/summary.md (routed, Vivado
//  2018.2), fpga/impl/default/*.txt and the verification runs.
// =====================================================================

// ---- Design parameters (competition build) ----
#let design = (
  image-w: 32,
  image-h: 32,
  kernel-n: 3,
  input-bits: 8,          // unsigned
  kernel-bits: 8,         // signed
  output-bits: 16,        // signed
  stride: 1,
  num-kernels: 1,
  architecture: [Streaming line buffer + DSP48E1 cascade MAC],
  macs: [9 DSP48E1 multiply–adds (one PCOUT→PCIN chain)],
  pipeline-stages: 16,    // register stages on the pixel path, excluding FIFO buffering
)

// ---- FPGA implementation (routed, 4.000 ns constraint) ----
#let fpga = (
  device: [AMD Zynq-7020 `xc7z020clg400-1` (PYNQ-Z2)],
  tool: [Vivado 2018.2],
  luts: 78,  luts-avail: 53200,
  ffs: 521,  ffs-avail: 106400,
  dsps: 9,   dsps-avail: 220,
  brams: 0,  brams-avail: 140,
  lutram: 24,
  srl: 17,
)

// ---- Timing, power & performance ----
#let perf = (
  clock-target: 4.000,          // ns (250 MHz)
  wns: 0.728,                   // ns
  tns: 0.000,
  whs: 0.082,
  fmax: 305.6,                  // MHz
  timing-met: [Yes],
  // Bars + Sobel-X benchmark
  power-dynamic: 0.015336,      // W
  power-static: 0.104585,
  power-total: 0.119921,
  // Checkerboard + Sobel-Y benchmark (headline)
  power-total-checker: 0.110615,
  power-dynamic-checker: 0.006163,
  power-static-checker: 0.104452,
  // Vivado vectorless estimate (reference only)
  power-vectorless: 0.159860,
  latency: 142,                 // cycles, first pixel -> first feature (32x32, QuestaSim)
  frame-cycles: 1041,           // cycles, first pixel -> last feature
  throughput: 1,                // output pixels per clock cycle, sustained
)

// ---- Verification ----
#let verif = (
  golden-lang: [Python 3 / NumPy],
  cases: [307 328],             // features compared by the 62-case hardware regression (87 frames)
  mismatches: 0,
  status: [Pass, bit-exact],
)

// =====================================================================
//  Derived quantities
// =====================================================================
#let clog2(x) = {
  let k = 0
  while calc.pow(2, k) < x { k += 1 }
  k
}

#let derived = {
  let d = design
  let n2 = d.kernel-n * d.kernel-n
  let in-max = calc.pow(2, d.input-bits) - 1
  let k-min = -calc.pow(2, d.kernel-bits - 1)
  let k-max = calc.pow(2, d.kernel-bits - 1) - 1
  (
    out-w: d.image-w - d.kernel-n + 1,
    out-h: d.image-h - d.kernel-n + 1,
    growth-bits: clog2(n2),
    prod-bits: d.input-bits + d.kernel-bits,
    acc-bits: d.input-bits + d.kernel-bits + clog2(n2),
    drop-bits: clog2(n2),
    in-max: in-max,
    k-min: k-min, k-max: k-max,
    prod-min: in-max * k-min, prod-max: in-max * k-max,
    acc-min: n2 * in-max * k-min, acc-max: n2 * in-max * k-max,
    out-min: -calc.pow(2, d.output-bits - 1),
    out-max: calc.pow(2, d.output-bits - 1) - 1,
  )
}

// Weighted area = LUTs + 50·DSPs + 100·BRAMs
#let weighted-area = fpga.luts + 50 * fpga.dsps + 100 * fpga.brams

// FoM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs))
#let fom = perf.throughput / (perf.power-total * weighted-area)
#let fom-checker = perf.throughput / (perf.power-total-checker * weighted-area)
#let fom-vectorless = perf.throughput / (perf.power-vectorless * weighted-area)

// Fixed-precision number formatting (keeps trailing zeros).
#let fix(x, digits: 3) = {
  let s = str(calc.round(x, digits: digits))
  let parts = s.split(".")
  let frac = if parts.len() > 1 { parts.at(1) } else { "" }
  if digits == 0 { parts.at(0) } else { parts.at(0) + "." + frac + "0" * (digits - frac.len()) }
}
