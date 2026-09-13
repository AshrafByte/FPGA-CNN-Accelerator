"""The run-directory contract between Python and hw/system/conv_system/src/tb/conv_image_tb.sv.

Three files change hands, all plain text under the run directory:

  stimulus.txt   written by write_stimulus, read by $fscanf in the testbench:
                     INPUT_SIZE WINDOW_SIZE NUM_KERNELS
                     NUM_KERNELS * WINDOW_SIZE**2 signed weights, kernel-major
                     INPUT_SIZE**2 pixels (0..255), raster order

  features.txt   written by the testbench, read by parse_results:
                     # comment
                     OUTPUT_SIZE NUM_KERNELS DROP
                     one raster line per output pixel, NUM_KERNELS values each

  sim.log        the simulator's combined stdout/stderr, kept for diagnosis

Geometry cannot travel in the file - INPUT_SIZE, WINDOW_SIZE and NUM_KERNELS
size the DUT at elaboration - so it is passed on the vsim command line as -g
overrides (see questa.py) and re-checked against the file header by the testbench.

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

from collections.abc import Sequence
from pathlib import Path

import numpy as np

from ..core.kernels import Kernel


class TestbenchError(RuntimeError):
    """The simulator could not be run, or the run did not honour the contract."""

    __test__ = False      # the name starts with "Test"; stop pytest collecting it


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
    """Read features.txt back into (num_kernels, output_size, output_size), plus DROP."""
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
