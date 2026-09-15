# experiments

Standalone builds used to justify the design choices of `hw/system/conv_system`: the three
multiply-accumulate (MAC) architectures it selects between, two variants of the rounding
stage, and the kernel-size sweep that compares them all.

## The three MAC architectures

Each build is the final `hw/` RTL (frame protocol, line buffer, FIFO, rounding - everything)
with `MAC_ARCH` fixed to one architecture and only that architecture's modules in its file
list, so a build measures one MAC and nothing else changes:

| Build | `MAC_ARCH` | MAC modules | `hw/` conv_system selects it when |
|---|---|---|---|
| `conv_single_chain` | 3 | `mac_single_chain`: all N² DSPs in one PCOUT->PCIN cascade | K = 1 and N <= 3 |
| `conv_row_chain` | 2 | `mac_row_chain`: one DSP cascade per window row + pipelined fabric tree | K = 1 and 4 <= N <= 8; K >= 2, N <= 8 and N²·K <= 180 |
| `conv_tree` | 1 | `multiplier_array` + `adder_tree`: N² parallel DSPs + pipelined fabric tree | every other N, K |

N = WINDOW_SIZE, K = NUM_KERNELS. `hw/` with `MAC_ARCH = 0` elaborates exactly the module its
rule names, so for any (N, K) it is identical to one of these builds.

## Rounding variants

Both are `hw/` with only `round_saturate` replaced (`src/round_saturate.sv`):

| Build | Output stage |
|---|---|
| `round_half_even` | round to nearest, ties to even, both clamps built (the earlier design) |
| `round_always_clamp` | round half up (as `hw/`) with the positive clamp built although it is unreachable |

`rounding/rounding_analysis.m` (MATLAB, copy of `docs/report/scripts/rounding_analysis.m`) gives
the numbers behind this choice: the error of truncation, round half up and round half to even over
every accumulator value a 3x3 window of 8-bit data can reach and on real convolutions, and the
saturation headroom of the 16-bit output for N = 2..17. Outputs go to `docs/report/figures/charts/`
(`rounding_error.png`, `saturation_headroom.png`, `rounding_*.csv`).

    matlab -batch "run('experiments/rounding/rounding_analysis.m')"   # from the repository root

## Checking a build in QuestaSim

Every build compiles its own `conv_system_tb` (the variants use the `hw/` testbench):

    cd experiments/conv_tree/system/conv_system/sim
    vlib work
    vlog -sv -timescale 1ns/1ps -F compile.f
    vsim -c work.conv_system_tb -gWINDOW_SIZE=5 -gNUM_KERNELS=2 -do "run -all; quit -f"

For `round_half_even` add `-gROUND_MODE=0` (the testbench's round-half-to-even model).
The architecture builds print `MAC_SEL=<1|2|3>` at elaboration.

These folders are outside `hw/` on purpose: CI lints every `.sv` under `hw/` together, and
each build here defines its own `conv_system`.

## Building a build in Vivado

`flow/scripts` is a copy of the competition flow in `fpga/scripts` (synth, impl, power) with three
more arguments, and every output goes to `flow/build/{synth,impl,reports,sim,logs}/<tag>`, so
`fpga/` and its competition results stay untouched:

| Argument | Default | Meaning |
|---|---|---|
| `RTL` | `hw` | `hw`, or a build of this folder (`conv_tree`, `conv_row_chain`, `conv_single_chain`, `round_half_even`, `round_always_clamp`) |
| `BENCH` | `auto` | power benchmark: `auto` (3x3: bars + Sobel-X and checker + Sobel-Y, else random) or `random` at every size |
| `MAX_DSP` | -1 | `synth_design -max_dsp` limit (-1 none); multipliers beyond it are built from LUTs |

The other arguments (`N`, `W`, `K`, `RELU`, `PERIOD`, `TAG`, `STEPS`) are those of `fpga/README.md`.

    vivado -mode batch -source experiments/flow/scripts/run_all.tcl -tclargs RTL conv_row_chain N 5
    vivado -mode batch -source experiments/flow/scripts/run_all.tcl -tclargs RTL round_half_even

Rounding variants at the competition point: `flow/build/reports/round_*_n3_w32_k1_r0_p4.000/`.

## Kernel-size sweep

`sweep/run_sweep.py` builds the three architectures for N = 2..17 (K = 1, no ReLU, 32 x 32,
6.25 ns / 160 MHz, random image and kernel for the power), one Vivado run at a time, and
writes `sweep/results.csv`. Builds that cannot fit the xc7z020 are not run and the reason is
recorded; after a failed build the larger sizes of that architecture are not continued:

- `conv_single_chain`: the one cascade must sit in one 60-slice DSP column, so N >= 8 is not run;
- `conv_row_chain`: needs N² DSPs and cannot use fabric multipliers, so N >= 15 (225 > 220) is not run;
- `conv_tree`: the only architecture that can spill multipliers into LUTs; N >= 15 is built
  with `MAX_DSP 200`.

    python experiments/sweep/run_sweep.py                 # all, reusing finished builds
    matlab -batch "run('experiments/sweep/sweep_charts.m')"   # MATLAB R2024a, from the repository root

Charts and tables land in `docs/report/figures/charts/sweep_*`. `sweep/sweep_charts.m` is a copy of
`docs/report/scripts/sweep_charts.m` (the report's figure script); both give the same output.

### Results (xc7z020, Vivado 2018.2, routed, 160 MHz)

35 builds were run and all completed; single cascade N >= 8 and row chains N >= 15 were not run
(no fit). FoM x 1e-3 (random image and kernel, SAIF power), best per N in bold:

| N | Single cascade | Row chains | Tree | System selects (% of best) |
|---|---|---|---|---|
| 2 | **32.3** | 30.5 | 25.9 | single cascade (100 %) |
| 3 | **15.3** | 14.2 | 11.0 | single cascade (100 %) |
| 4 | **8.40** | 7.75 | 5.79 | row chains (92.3 %) |
| 5 | 5.06 | **5.11** | 3.47 | row chains (100 %) |
| 6 | 3.17 | **3.18** | 2.17 | row chains (100 %) |
| 7 | 1.89 | **2.11** | 1.49 | row chains (100 %) |
| 8 | no fit | **1.48** | 1.04 | row chains (100 %) |
| 9 | - | **1.05** | 0.757 | tree (72.1 %) |
| 10 | - | **0.641** | 0.566 | tree (88.3 %) |
| 11 | - | **0.483** | 0.407 | tree (84.3 %) |
| 12 | - | 0.362 | **0.388** | tree (100 %) |
| 13 | - | 0.281 | **0.321** | tree (100 %) |
| 14 | - | 0.217 | **0.257** | tree (100 %) |
| 15 | - | no fit | **0.184** | tree, 200 DSP + LUT multipliers (100 %) |
| 16 | - | - | **0.137** | tree, 200 DSP + LUT multipliers (100 %) |
| 17 | - | - | **0.105** | tree, 200 DSP + LUT multipliers (100 %), 156.3 MHz |

- Single cascade: fewest LUTs (52 -> 210), skew FFs grow as N^4 (226 -> 10 062 at 7x7), one DSP column.
- Row chains: skew grows as N^3, up to 196 DSPs; best FoM for N = 5..11; Fmax 162-171 MHz from N = 5.
- Tree: most LUTs, no skew, highest Fmax from N = 4, the only one that continues past 220 DSPs.

The system's limits (`CHAIN_MAX_N = 3`, `ROW_CHAIN_MAX_N = 8`) were chosen for 250 MHz with
timing margin. At 160 MHz the best boundaries are N <= 4 single cascade, 5..11 row chains, 12+ tree,
i.e. `CHAIN_MAX_N = 4`, `ROW_CHAIN_MAX_N = 11`.
