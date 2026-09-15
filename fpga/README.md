# FPGA implementation and board demo

Vivado flow for `conv_system` (the RTL in `hw/`) on the PYNQ-Z2 (`xc7z020clg400-1`):
synthesis, implementation, benchmark power and figure of merit, and a PYNQ overlay
that runs the accelerator from the Zynq processing system (board demonstration bonus).

Tested with Vivado 2018.2 (xsim for the power stimulus). Every script reads the RTL
through `hw/system/conv_system/sim/rtl.f`, the same file list the simulators use.

## Layout

```
fpga/
├── run.ps1                 Windows entry point (wraps scripts/run_all.tcl)
├── scripts/
│   ├── config.tcl          arguments, paths, helpers (sourced by every step)
│   ├── run_all.tcl         runs the selected steps in one Vivado session
│   ├── board_sim.tcl       self-checking xsim test of the board AXI wrapper
│   ├── synth.tcl           -> synth/<tag>/
│   ├── impl.tcl            -> impl/<tag>/
│   ├── power.tcl           -> reports/<tag>/  (benchmark SAIF power, FoM)
│   └── bitstream.tcl       -> bitstream/      (PYNQ-Z2 overlay)
├── constraints/
│   └── conv_system.xdc     250 MHz clock of the standalone build
├── sim/
│   ├── conv_system_power_tb.sv   benchmark stimulus for the SAIF
│   └── saif.tcl
├── synth/<tag>/            post_synth.dcp, utilization, timing
├── impl/<tag>/             post_route.dcp, utilization (flat + hierarchy), timing, DRC, route status, vectorless power
├── reports/<tag>/          summary.md, results.csv, power_<benchmark>.txt
├── bitstream/              conv_demo.bit, conv_demo.hwh, conv_demo.txt, reports/
└── board/
    ├── rtl/conv_axi_lite.sv      AXI4-Lite register front end + result memories
    ├── rtl/conv_demo_top.sv      block design wrapper + conv_axi_lite + LEDs
    ├── constraints/pynq_z2.xdc   user LEDs
    ├── tb/conv_axi_lite_tb.sv    self-checking wrapper testbench
    ├── tests/test_conv_demo_driver.py   driver test against a register model (pytest, no board)
    └── pynq/conv_demo.py         board driver, golden model, command-line demo
        pynq/conv_demo.ipynb      Jupyter demo
```

`<tag>` is `default` for the competition build and `n<N>_w<W>_k<K>_r<RELU>_p<PERIOD>`
otherwise. Checkpoints (`*.dcp`), the demo's Vivado project (`bitstream/build/`), simulator
scratch (`sim/build/`) and logs (`logs/`) are git-ignored; reports and the overlay are kept.

## Running

Windows (PowerShell, from the repository root):

```powershell
.\fpga\run.ps1                                  # synth, impl, power, bitstream - default build
.\fpga\run.ps1 -Steps synth,impl,power          # FoM only
.\fpga\run.ps1 -Steps board_sim                 # AXI wrapper test
.\fpga\run.ps1 -Steps synth,impl,power -N 5 -W 64 -K 2
```

`run.ps1` finds Vivado through `XILINX_VIVADO`, the `PATH`, or `D:\Vivado\2018.2` /
`C:\Xilinx\Vivado\2018.2`; pass `-Vivado <path to vivado.bat>` otherwise.

Linux / make:

```bash
make fpga                                   # synth + impl + power + bitstream
make fpga-power FPGA_ARGS="N 5 W 64"
make fpga-board-sim
```

Plain Vivado (arguments are key/value pairs without `=`, which `vivado.bat` strips):

```bash
vivado -mode batch -source fpga/scripts/run_all.tcl -tclargs STEPS synth+impl+power N 3 W 32
```

| Argument | Default | Meaning |
|---|---|---|
| `N` | 3 | kernel size (WINDOW_SIZE) |
| `W` | 32 | image width and height (INPUT_SIZE) |
| `K` | 1 | kernel lanes (NUM_KERNELS) |
| `RELU` | 0 | ENABLE_RELU |
| `PERIOD` | 4.000 | clock period in ns for synth / impl / power |
| `TAG` | derived | output folder name |
| `STEPS` | `synth+impl+power+bitstream` | steps for `run_all.tcl` (`board_sim` also available) |
| `JOBS` | 4 | threads for the bitstream runs |
| `BUILD` | see below | Vivado project directory of the board demo |

The board demo is a Vivado project whose generated IP paths are about 150 characters deep.
Windows rejects paths over 260 characters, so under a long checkout path the project is
created in `%TEMP%\conv_demo_build` (elsewhere: `fpga/bitstream/build/`); pass `BUILD <dir>`
to choose. The overlay and its reports are always copied to `fpga/bitstream/`.

The MAC architecture follows the automatic selection in `conv_system.sv`
(single chain for 3x3 with one kernel, row chains up to 8x8, tree beyond).

## Steps

**synth** - non-project `synth_design` of `conv_system` with the requested generics and a
clock constraint made from `constraints/conv_system.xdc`.

**impl** - `opt_design`, `place_design`, `phys_opt_design`, `route_design` on the synthesis
checkpoint, then utilization, timing, route status, DRC and vectorless power.

**power** - the figure of merit of the competition:

    FoM = Throughput / (Power [W] x (LUTs + 50 DSPs + 100 BRAMs))

Throughput is 1 output pixel per clock cycle, the sustained rate of `conv_system` once its
output FIFO is primed. Power comes from switching activity: `sim/conv_system_power_tb.sv`
streams one full frame through the RTL in xsim, the SAIF is annotated on the routed
checkpoint and `report_power` gives the on-chip total. The benchmarks are

| Benchmark | Image | Kernel |
|---|---|---|
| `bars_sobel_x` | vertical bars, 4 px black / 4 px white | Sobel-X |
| `checker_sobel_y` | pixel checkerboard 0x00 / 0xFF (every input bit toggles every cycle) | Sobel-Y |
| `random` (N != 3) | uniform random pixels | random int8 weights |

`reports/<tag>/summary.md` also lists the vectorless estimate (Vivado default activity) for
reference. A SAIF is re-simulated only when an RTL source or the testbench is newer.

**bitstream** - the board demo, see below. Its clock is the 100 MHz fabric clock of the
processing system; the FoM build above is the standalone 250 MHz one.

**board_sim** - `board/tb/conv_axi_lite_tb.sv` drives the AXI wrapper exactly like the PYNQ
driver (one soft reset, kernels, pixel bursts, status polling, feature read-back) on three
builds - 3x3/32 with one and two lanes, 5x5/16 with ReLU. Five frames follow the single
reset with no reset between them (three with new kernels, one with the same kernels), then
a sixth frame after a second soft reset; every feature is compared with a behavioural
model, and OUT_COUNT, PIXEL_COUNT, WEIGHT_COUNT and FRAME_COUNT are checked per frame.

## Results - default build

3x3 kernel, 32x32 image, one kernel, no ReLU, 4.000 ns (250 MHz), Vivado 2018.2, routed.
Full tables: [reports/default/summary.md](reports/default/summary.md).

| LUT | FF | DSP | BRAM | LUT + 50 DSP + 100 BRAM | WNS | Fmax |
|---|---|---|---|---|---|---|
| 78 | 521 | 9 | 0 | 528 | +0.728 ns | 305.6 MHz |

| Workload | Total power | Dynamic | FoM |
|---|---|---|---|
| Bars + Sobel-X | 119.921 mW | 15.336 mW | **0.01579** |
| Checker + Sobel-Y | 110.615 mW | 6.163 mW | **0.01712** |
| Vectorless (reference only) | 159.860 mW | 54.699 mW | 0.01185 |

The MAC is the single DSP48E1 chain (MAC_SEL 3). The build streams frames back to back
without a reset (`o_frame_done`); that frame protocol costs 7 LUTs over the single-frame
build (71 LUT, +0.794 ns, FoM 0.01596 / 0.01730): a one-hot row ring and a flip-flop
frame-end delay line add flip-flops only, and the FIFO's frame re-arm adds 6 LUTs. Only 7% of
nets match the SAIF because registers absorbed into the DSP slices lose their RTL names;
the rest of the activity is propagated by Vivado.

## Board demonstration (PYNQ-Z2)

### Hardware

```
 Zynq PS (ARM) ── M_AXI_GP0 ── AXI interconnect ── M_AXI (AXI4-Lite, 0x43C00000, 1 MB)
      │ FCLK_CLK0 100 MHz + proc_sys_reset                    │
      └───────────────────────────────────────────── conv_axi_lite ── conv_system
                                                               └─ LEDs
```

`conv_axi_lite` accepts kernels and pixels as register writes and feeds them to
`conv_system` one per clock cycle (`PIXELS4` carries four pixels per write). Every output
feature is stored in a block-RAM result memory per lane that the host reads back.

| Offset | Register | Access | Content |
|---|---|---|---|
| 0x000 | ID | RO | 0x434E5631 ("CNV1") |
| 0x004 | GEOMETRY | RO | [15:0] INPUT_SIZE, [23:16] WINDOW_SIZE, [31:24] NUM_KERNELS |
| 0x008 | FORMAT | RO | [7:0] feature bits, [15:8] IDX_BITS, [16] ENABLE_RELU |
| 0x00C | CTRL | RW | [0] soft reset (write 1, then 0) |
| 0x010 | STATUS | RO | [0] weights loaded, [1] streaming, [2] frame done |
| 0x014 | KERNEL_SEL | RW | lane loaded by WEIGHT writes |
| 0x018 | WEIGHT | WO | next weight (int8), tap order |
| 0x01C | PIXEL | WO | next pixel |
| 0x020 | PIXELS4 | WO | four pixels, byte 0 first |
| 0x024 | WEIGHT_COUNT | RO | weights accepted since reset |
| 0x028 / 0x02C | PIXEL_COUNT / OUT_COUNT | RO | pixels / features of the current frame |
| 0x030 / 0x034 | LATENCY / FRAME_CYCLES | RO | cycles from the frame's first pixel to its first / last feature |
| 0x038 | FRAME_COUNT | RO | frames completed since reset (`o_frame_done` pulses) |
| 0x10000 + (k << (IDX_BITS+2)) + 4i | feature i of lane k | RO | sign-extended int16 |

Start-up: `CTRL=1`, `CTRL=0` once; per lane `KERNEL_SEL=k` and the N² weights, each kernel
row written right to left (a new window column enters at column 0 - the same order as
`sw/conv_lab` `pack_kernel`). Every frame: the W² pixels; poll `STATUS[2]`; read the
features. Frames follow each other **without a reset**: `STATUS[2]` is set by
`conv_system`'s `o_frame_done` and cleared by the next frame's first pixel, which also
restarts the per-frame counters. A new kernel can be written between frames. The result
memory holds one frame, so read it before sending the next.

LEDs: LD0 weights loaded, LD1 streaming, LD2 frame done, LD3 heartbeat.

### Build

```powershell
.\fpga\run.ps1 -Steps bitstream                 # fpga/bitstream/conv_demo.bit + .hwh
.\fpga\run.ps1 -Steps bitstream -K 2 -W 64      # other overlay configurations
```

The bitstream step always writes `fpga/bitstream/conv_demo.*`, so building another configuration
replaces the delivered overlay; keep a copy first.

Default overlay (3x3, 32x32, one kernel): 813 LUT, 9 DSP, 0.5 BRAM tile for the whole
demo (AXI interconnect, wrapper, result memory and conv_system), WNS +2.560 ns at 100 MHz,
bitstream in about 7 minutes. `conv_demo.hwh` maps `M_AXI` at 0x43C00000-0x43CFFFFF with
FCLK_CLK0 = 100 MHz. The power in `bitstream/reports/power.txt` includes the processing
system and is not the FoM power, which comes from the standalone build above.

The block design uses the `processing_system7` defaults plus the GP0 master and FCLK_CLK0;
PYNQ keeps its own boot-time PS configuration and applies the clock settings from the `.hwh`,
so no board preset is needed.

### Run on the board

1. Boot the PYNQ-Z2 with a PYNQ image (v2.4 or later) and open Jupyter at `http://<board>:9090`.
2. Copy `fpga/bitstream/conv_demo.bit`, `fpga/bitstream/conv_demo.hwh`,
   `fpga/board/pynq/conv_demo.py` and `fpga/board/pynq/conv_demo.ipynb` into one folder,
   e.g. `/home/xilinx/jupyter_notebooks/conv_demo/`.
3. Open `conv_demo.ipynb` and run all cells, or from a terminal on the board:

```bash
sudo python3 conv_demo.py                               # patterns x Sobel, Laplacian, Gaussian, sharpen
sudo python3 conv_demo.py --image photo.jpg --kernels sobel_x sobel_y --save edges.png
```

Every hardware frame is compared feature by feature with the golden model in
`conv_demo.py` (identical to `sw/conv_lab/core/reference.py`: valid correlation, round half
up, 16-bit saturation); the script prints the mismatches per frame and exits with 1 on any.
The driver resets the accelerator once when it opens the overlay; every frame after that
streams without a reset, and a kernel is rewritten only when it changes.
`python conv_demo.py --model-only` runs the model alone on any machine.

### Verification before the board

- `board_sim`: all features of all lanes bit-exact through AXI on the three builds, over
  five frames without a reset and a sixth after a soft reset.
- `board/tests/test_conv_demo_driver.py`: the PYNQ driver against a register-level model of
  `conv_axi_lite` + `conv_system` (no board needed). It checks that the driver resets once,
  rewrites a kernel only when it changes, streams frames without a reset, sends each kernel
  row in hardware tap order, and reads back two lanes with ReLU:

```bash
python -m pytest fpga/board/tests
```
- The demo's golden model was checked against `sw/conv_lab/core/reference.py` on 135
  frames (random kernels of 1x1 to 7x7 with and without ReLU, every demo kernel on every pattern).
