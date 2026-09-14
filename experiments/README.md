# experiments

The three multiply-accumulate architectures that `hw/system/conv_system`
selects between, each kept as a complete, standalone build with
the same layout as `hw/`:

| Build | MAC architecture | Used by `hw/` conv_system when |
|---|---|---|
| `conv_tree` | `multiplier_array` + `adder_tree` (full fabric adder tree) | K = 1 and N >= 9; K >= 2 unless N <= 8 and N^2*K <= 180 |
| `conv_row_chain` | `mac_cascade`: one DSP chain per window row + short fabric tree (full-width tree) | K = 1 and 4 <= N <= 8; K >= 2 and N <= 8 and N^2*K <= 180 |
| `conv_single_chain` | `mac_cascade`: all N^2 DSPs in one PCOUT->PCIN chain, `max_fanout = 24` on the pixel write enable | K = 1 and N <= 3 |

N = WINDOW_SIZE, K = NUM_KERNELS. All three round half up; everything outside
the MAC is the same as `hw/`. `hw/ip/mac_row_chain` is `conv_row_chain`'s `mac_cascade`
with a bit-growing reduction tree; `hw/ip/mac_single_chain` is `conv_single_chain`'s.

Measured at 3x3, 32x32, K = 1, 250 MHz (xc7z020, Vivado 2018.2):

| | `conv_tree` | `conv_row_chain` | `conv_single_chain` |
|---|---|---|---|
| LUT / FF / DSP / BRAM | 205 / 429 / 9 / 0 | 110 / 322 / 9 / 0 | 70 / 474 / 9 / 0 |
| WNS | +0.751 ns | +0.543 ns | +0.757 ns |
| FoM, bars + Sobel-X | 0.01226 | 0.01483 | 0.01597 |
| FoM, checkerboard + Sobel-Y | 0.01227 | 0.01612 | 0.01731 |

These folders are outside `hw/` on purpose: CI lints every `.sv` under `hw/`
together, and each build here defines its own `conv_system`. vrun.py only
discovers `hw/` and `verif/`, so compile a build by hand from its sim folder:

    cd experiments/conv_single_chain/system/conv_system/sim
    vlog -sv -timescale 1ns/1ps -F compile.f
    vsim -c work.conv_system_tb -gWINDOW_SIZE=3 -gNUM_KERNELS=1 -do "run -all; quit -f"
