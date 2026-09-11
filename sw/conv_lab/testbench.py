"""The bridge between Python and hw/system/conv_system/src/tb/conv_image_tb.sv.

Questa (vlib/vlog/vsim) is the only supported simulator.

CONTRACT
========

    run(image, kernels) -> TestbenchResult

`image` is an (N, N) uint8 array, `kernels` a sequence of Kernel. One call
elaborates conv_system for that exact geometry, streams one frame, and returns
every feature the hardware emitted, as int32 of shape (len(kernels), N-K+1, N-K+1).

Three files change hands, all plain text under the run directory:

  stimulus.txt   written here, read by $fscanf in the testbench:
                     INPUT_SIZE WINDOW_SIZE NUM_KERNELS
                     NUM_KERNELS * WINDOW_SIZE**2 signed weights, kernel-major
                     INPUT_SIZE**2 pixels (0..255), raster order

  features.txt   written by the testbench, parsed here:
                     # comment
                     OUTPUT_SIZE NUM_KERNELS DROP
                     one raster line per output pixel, NUM_KERNELS values each

  sim.log        the simulator's combined stdout/stderr, kept for diagnosis

Geometry cannot travel in the file - INPUT_SIZE, WINDOW_SIZE and NUM_KERNELS
size the DUT at elaboration - so it is passed on the vsim command line as -g
overrides and re-checked against the file header by the testbench.

THE ONE TRAP: TAP ORDER
=======================

window_generator shifts each new pixel column in at index 0, so the flattened
window the multipliers see is row-ascending but column-DESCENDING:

    window[kr*K + kc] == image[row + kr][col + (K-1-kc)]

Loading a kernel verbatim would therefore compute a column-mirrored result.
`pack_kernel` reverses each row on the way out so the hardware computes the
ordinary correlation the user drew. Everything above this function - the golden
model, the display, the presets - works in natural row-major order.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import time
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Final

import numpy as np

from .imaging import validate_dimensions
from .kernels import Kernel
from .reference import drop_bits

REPO_ROOT: Final = Path(__file__).resolve().parents[2]
MANIFEST: Final = REPO_ROOT / "hw" / "system" / "conv_system" / "sim" / "compile.f"
TOP: Final = "conv_image_tb"
DEFAULT_RUN_DIR: Final = REPO_ROOT / "sw" / ".run"

#: Simulation gets slow long before it gets wrong; this is a stall guard.
TIMEOUT_S: Final = 1800


class TestbenchError(RuntimeError):
    """The simulator could not be run, or the run did not produce a full frame."""


@dataclass(frozen=True, slots=True)
class TestbenchResult:
    features: np.ndarray  # (num_kernels, out_size, out_size), int32
    drop_bits: int
    elapsed_s: float
    run_dir: Path
    log: str

    @property
    def output_size(self) -> int:
        return int(self.features.shape[1])


# --------------------------------------------------------------------------- #
# Stimulus / result files
# --------------------------------------------------------------------------- #

def pack_kernel(kernel: Kernel) -> list[int]:
    """Flatten a kernel into hardware tap order - see THE ONE TRAP above."""
    return [w for row in kernel.rows for w in reversed(row)]


def write_stimulus(path: Path, image: np.ndarray, kernels: Sequence[Kernel]) -> None:
    window = kernels[0].size
    lines = [f"{image.shape[0]} {window} {len(kernels)}"]
    lines += [" ".join(str(w) for w in pack_kernel(k)) for k in kernels]
    lines += [" ".join(str(p) for p in row) for row in image.tolist()]
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def parse_results(path: Path, num_kernels: int, output_size: int) -> tuple[np.ndarray, int]:
    """Read features.txt back into (num_kernels, output_size, output_size)."""
    if not path.is_file():
        raise TestbenchError(f"the testbench produced no result file at {path}")

    rows = [line.split() for line in path.read_text(encoding="ascii").splitlines()
            if line.strip() and not line.lstrip().startswith("#")]
    if not rows:
        raise TestbenchError(f"result file {path} is empty")

    header, *body = rows
    if len(header) != 3:
        raise TestbenchError(f"malformed result header in {path}: {' '.join(header)!r}")

    got_size, got_kernels, drop = (int(v) for v in header)
    if (got_size, got_kernels) != (output_size, num_kernels):
        raise TestbenchError(
            f"result header says {got_size}x{got_size} x {got_kernels} kernel(s), "
            f"expected {output_size}x{output_size} x {num_kernels}"
        )

    expected = output_size * output_size
    if len(body) != expected:
        raise TestbenchError(f"expected {expected} feature row(s) in {path}, got {len(body)}")

    try:
        flat = np.array([[int(v) for v in row] for row in body], dtype=np.int32)
    except ValueError as exc:
        raise TestbenchError(f"non-integer feature value in {path}: {exc}") from exc

    if flat.shape[1] != num_kernels:
        raise TestbenchError(
            f"expected {num_kernels} value(s) per line in {path}, got {flat.shape[1]}"
        )

    # (pixels, kernels) -> (kernels, row, col)
    return flat.T.reshape(num_kernels, output_size, output_size), drop


# --------------------------------------------------------------------------- #
# Simulator backends
# --------------------------------------------------------------------------- #

def questa_steps(run_dir: Path, input_size: int, window: int,
                 num_kernels: int) -> list[str]:
    """The vlib/vlog/vsim sequence for one frame, run from `run_dir`."""
    if shutil.which("vsim") is None:
        raise TestbenchError(
            "Questa not found on PATH (no vsim). Install it, or pass --reference "
            "to compute with the Python model instead."
        )
    generics = " ".join(
        f"-g{name}={value}"
        for name, value in (("INPUT_SIZE", input_size),
                            ("WINDOW_SIZE", window),
                            ("NUM_KERNELS", num_kernels))
    )
    # Whether the library already exists is decided here rather than with a
    # shell conditional: cmd.exe binds `&&` inside an `if`, so `if not exist
    # work vlib work && vlog ...` would swallow the whole rest of the chain on
    # every run after the first.
    steps = [] if (run_dir / "work").is_dir() else ["vlib work"]

    # No source file carries a `timescale directive, so pin one rather than
    # inheriting whatever the local modelsim.ini happens to set as Resolution.
    steps += [
        f'vlog -sv -quiet -timescale 1ns/1ps -F "{MANIFEST}"',
        f'vsim -c {generics} work.{TOP} '
        f'+stim=stimulus.txt +result=features.txt -do "run -all; quit -f"',
    ]
    return steps


# --------------------------------------------------------------------------- #
# Run
# --------------------------------------------------------------------------- #

def run(
    image: np.ndarray,
    kernels: Sequence[Kernel],
    *,
    run_dir: Path | None = None,
    echo: bool = False,
) -> TestbenchResult:
    """Convolve `image` with every kernel in `kernels` on the SystemVerilog testbench."""
    if not kernels:
        raise TestbenchError("no kernels given")

    sizes = {k.size for k in kernels}
    if len(sizes) != 1:
        raise TestbenchError(
            f"all kernels in one run must be the same size; got {sorted(sizes)}"
        )

    window = sizes.pop()
    validate_dimensions(*image.shape, window)
    if not MANIFEST.is_file():
        raise TestbenchError(f"missing compile manifest {MANIFEST}")

    input_size = int(image.shape[0])
    output_size = input_size - window + 1
    run_dir = Path(run_dir or DEFAULT_RUN_DIR)
    run_dir.mkdir(parents=True, exist_ok=True)

    result_path = run_dir / "features.txt"
    result_path.unlink(missing_ok=True)
    write_stimulus(run_dir / "stimulus.txt", image, kernels)

    steps = questa_steps(run_dir, input_size, window, len(kernels))
    started = time.monotonic()
    log = _shell(steps, cwd=run_dir, echo=echo)
    elapsed = time.monotonic() - started
    (run_dir / "sim.log").write_text(log, encoding="utf-8", errors="replace")

    if "STATUS: OK" not in log:
        raise TestbenchError(
            f"the Questa run did not complete - see {run_dir / 'sim.log'}\n\n"
            + _tail(log)
        )

    features, drop = parse_results(result_path, len(kernels), output_size)
    if drop != drop_bits(window):
        raise TestbenchError(
            f"hardware reports DROP={drop} but the reference model assumes "
            f"{drop_bits(window)} - the models have diverged"
        )

    return TestbenchResult(
        features=features,
        drop_bits=drop,
        elapsed_s=elapsed,
        run_dir=run_dir,
        log=log,
    )


def _shell(steps: Sequence[str], *, cwd: Path, echo: bool) -> str:
    """Run the steps as one shell session, stopping at the first failure."""
    if os.name == "nt":
        command = " && ".join(steps)
        executable = None
    else:
        # set -e gives the same stop-on-first-failure that cmd's && chain does.
        command = "set -e\n" + "\n".join(steps)
        executable = "/bin/bash"

    if echo:
        for step in steps:
            print(f"    $ {step}")

    try:
        proc = subprocess.run(
            command,
            cwd=cwd,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=TIMEOUT_S,
            shell=True,
            executable=executable,
        )
    except subprocess.TimeoutExpired as exc:
        raise TestbenchError(f"simulation exceeded {TIMEOUT_S}s and was killed") from exc

    return proc.stdout + proc.stderr


def _tail(log: str, lines: int = 15) -> str:
    return "\n".join(log.splitlines()[-lines:])

