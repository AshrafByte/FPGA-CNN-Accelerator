# conv_lab

Pick an image, pick a kernel, run the convolution **on the SystemVerilog
testbench**, and see the hardware's output next to the input — checked
bit-for-bit against a software model of the same pipeline.

```
image (N x N uint8) ─┐
                     ├─► stimulus.txt ─► conv_image_tb ─► features.txt ─► side by side
kernel(s) ───────────┘                   (conv_system)                    + MATCH / MISMATCH
```

## Install

```bash
python -m pip install -r sw/requirements.txt
```

Plus QuestaSim, with `vlib`/`vlog`/`vsim` on `PATH`. It is the only supported
simulator; without it, only `--reference` works.

## Use

```bash
cd sw
python -m conv_lab                                    # interactive
python -m conv_lab --list-kernels                     # what's available
python -m conv_lab --image photo.jpg --size 64 --kernel sobel_x
python -m conv_lab --pattern circle --size 32 --kernel sobel_x --kernel sobel_y
python -m conv_lab --pattern ramp --size 16 --weights '1 0 -1; 2 0 -2; 1 0 -1'
python -m conv_lab --pattern checker --size 32 --kernel laplacian --png out.png --csv out.csv
python -m conv_lab --image photo.jpg --size 64 --kernel sharpen --reference   # no simulator
```

Any image format Pillow reads is accepted; it is converted to a single channel
and resized to `--size` x `--size`. `--pattern` substitutes a synthetic frame
(`ramp`, `checker`, `circle`, `bars`, `noise`) when the point is the hardware
rather than the picture.

Kernels come from `--kernel` (presets), `--weights` (custom), or both, and
repeating either flag loads several lanes into one run — the hardware evaluates
them in parallel, so five kernels cost the same simulated time as one. Custom
weights accept whatever you paste:

```
1 0 -1; 2 0 -2; 1 0 -1
[[1, 0, -1], [2, 0, -2], [1, 0, -1]]
```

Exit status is 0 when every feature matched the model, 1 when the hardware
disagreed or the simulator failed, 2 for bad input.

## Two compute paths

| | computes with | needs Questa | prints |
| --- | --- | --- | --- |
| default | `conv_image_tb` on the RTL, then checks it | yes | `hardware` + `model` + `MATCH`/`MISMATCH` |
| `--reference` | the Python model only | no | `model` |

`--reference` swaps the testbench out for `reference.convolve`. Same arithmetic,
same geometry rules, same output frames — the model is bit-accurate, so the
numbers are what the hardware would emit. What is missing is any *evidence* that
the RTL agrees, so nothing was near the DUT and no verdict is printed. Use it to
try kernels quickly, or to see what a preset does before committing simulation
time; use the default path when you need the RTL checked.

## Presets

| Kernel | Sum | Gain | Notes |
| --- | ---: | ---: | --- |
| `identity` | 16 | 1.000 | pass-through |
| `sobel_x` / `sobel_y` | 0 | — | gradient, vertical / horizontal edges |
| `prewitt_x` / `prewitt_y` | 0 | — | unweighted gradient |
| `scharr_x` | 0 | — | better rotational symmetry than Sobel |
| `laplacian` / `laplacian_8` | 0 | — | second derivative, 4- and 8-neighbour |
| `gaussian_blur` | 16 | 1.000 | unity gain, see below |
| `box_blur` | 9 | 0.562 | mean filter, comes out dim |
| `sharpen` | 16 | 1.000 | unsharp mask |
| `emboss` | 16 | 1.000 | directional relief |

**Why the weights are not normalised.** The weight bus is signed 8-bit, so
presets carry their integer form. The divide is supplied by the pipeline:
`round_saturate` drops `$clog2(K**2)` low bits, which is a built-in `>>4` for a
3x3 window. A kernel whose weights sum to 16 is therefore unity gain — which is
why `gaussian_blur` looks right and `box_blur` (sum 9) comes out at 9/16
brightness. `--list-kernels` prints the gain for each.

## Interface to the hardware

```python
from conv_lab import preset, run
from conv_lab.imaging import load_image

image  = load_image("photo.jpg", 64)      # (64, 64) uint8
result = run(image, [preset("sobel_x")])  # elaborate, stream one frame, read back
result.features                           # (1, 62, 62) int32, signed features
```

`run()` is the whole contract. It validates the geometry, writes the stimulus,
elaborates `conv_system` for that exact shape, streams one frame, and parses the
features back. It raises `TestbenchError` if the simulator is missing, the run
fails, or the frame comes back short.

| | |
| --- | --- |
| `image` | `(N, N)` `uint8`, square, `N > K`, `N <= 512` |
| `kernels` | one or more `Kernel`, all the same odd size, weights in `[-128, 127]` |
| returns | `TestbenchResult` with `features` as `(len(kernels), N-K+1, N-K+1)` `int32` |

Output is **valid-only** — no padding, so an N x N frame gives (N-K+1) squared
features — and each value is already `MAC >> drop_bits` with round-half-to-even.

### Files exchanged

Three text files, under `sw/.run/` by default (`--run-dir` to move it):

`stimulus.txt`, written by Python and read by `$fscanf`:

```
INPUT_SIZE WINDOW_SIZE NUM_KERNELS
<NUM_KERNELS * WINDOW_SIZE**2 signed weights, kernel-major>
<INPUT_SIZE**2 pixels 0..255, raster order>
```

`features.txt`, written by the testbench:

```
# comment
OUTPUT_SIZE NUM_KERNELS DROP
<one raster line per output pixel, NUM_KERNELS signed values each>
```

`sim.log` — the simulator's combined output, kept for diagnosis.

Geometry cannot travel in the file: `INPUT_SIZE`, `WINDOW_SIZE` and
`NUM_KERNELS` size the DUT at elaboration, so they are passed to `vsim` as `-g`
overrides *and* repeated in the file header, which the testbench checks. A forgotten override is a clear error rather than a
silently truncated image.

The testbench is usable without Python:

```bash
vlib work
vlog -sv -timescale 1ns/1ps -F hw/system/conv_system/sim/compile.f
vsim -c -gINPUT_SIZE=32 work.conv_image_tb \
     +stim=stimulus.txt +result=features.txt -do "run -all; quit -f"
```

Run these from the directory holding `stimulus.txt` — the testbench opens the
plusarg paths relative to the simulator's working directory.

### The one trap: tap order

`window_generator` shifts each new pixel column in at index 0, so the flattened
window the multipliers see is row-ascending but **column-descending**:

```
window[kr*K + kc] == image[row + kr][col + (K-1-kc)]
```

Loading a kernel verbatim would compute a column-mirrored result. `pack_kernel`
reverses each row on the way into `stimulus.txt`, so the hardware computes the
correlation you actually drew. Everything above that function — presets, the
golden model, the display — is in natural row-major order.

This is the failure that hides: it is invisible on any symmetric kernel
(`box_blur`, `gaussian_blur`, `laplacian`) and only shows up as a sign flip on
`sobel_x`. `tests/test_conv_lab.py` replays the DUT's indexing in Python and
asserts the flip is what turns it back into a correlation.

## What the check actually proves

Each run compares the hardware's frame against `reference.convolve`, an
independent model of MAC → round-half-to-even → saturate. The result is
`MATCH` only when every feature is bit-exact.

Worth knowing: the 16-bit saturation clamp is **unreachable** with this
parameterisation. `DROP` is `$clog2(K**2)`, so the worst case is
`255 * 128 * K**2 >> $clog2(K**2)`, at most `255 * 128 = 32640` — inside the
signed 16-bit range for every odd K. The clamp only starts earning its keep if
`PIXEL_WIDTH` or `FEATURE_WIDTH` changes.

## Layout

```
sw/conv_lab/kernels.py     presets, custom-weight parsing, range checks
sw/conv_lab/imaging.py     loading, synthetic patterns, normalising, ASCII + PNG
sw/conv_lab/reference.py   bit-accurate model of the datapath
sw/conv_lab/testbench.py   the bridge: stimulus, simulator, results
sw/conv_lab/display.py     side-by-side panels, stats, the verdict
sw/conv_lab/cli.py         argument handling and the interactive flow
sw/tests/                  everything checkable without a simulator
```

```bash
cd sw && python -m pytest tests -q
```

The hardware half lives in
[`hw/system/conv_system/src/tb/conv_image_tb.sv`](../hw/system/conv_system/src/tb/conv_image_tb.sv),
compiled through `hw/system/conv_system/sim/compile.f` (via `tb.f`, alongside
the existing self-checking `conv_system_tb`, which is untouched). It is a pure
harness — no stimulus, no expectations of its own.

## First run on a new machine

**Run a non-default size first:**

```bash
python -m conv_lab --pattern circle --size 16 --kernel sobel_x --verbose
```

`conv_image_tb`'s parameters default to `INPUT_SIZE=32, WINDOW_SIZE=3,
NUM_KERNELS=1`. A 32x32 single-kernel run therefore still passes even if the
`-g` overrides are silently ignored, because the defaults happen to be right.
Size 16 makes a broken override fail loudly, with the testbench reporting the
exact mismatch it saw. Once that passes, the geometry path is proven and any
size works.
