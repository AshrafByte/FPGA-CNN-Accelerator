"""Kernel presets and parsing for custom weights.

Every weight has to survive the hardware's signed 8-bit weight bus, so the
presets here are the integer forms of the classic kernels - no normalising
divisor. The divisor is effectively supplied by the pipeline itself: see
`Kernel.hardware_gain`.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Final, Self

WEIGHT_MIN: Final = -128
WEIGHT_MAX: Final = 127


class KernelError(ValueError):
    """A kernel is malformed or cannot be represented by the hardware."""


@dataclass(frozen=True, slots=True)
class Kernel:
    """A square, odd-sized integer kernel the accelerator can load."""

    name: str
    rows: tuple[tuple[int, ...], ...]
    description: str = ""

    def __post_init__(self) -> None:
        if not self.rows:
            raise KernelError(f"kernel {self.name!r} is empty")

        size = len(self.rows)
        if any(len(row) != size for row in self.rows):
            widths = sorted({len(row) for row in self.rows})
            raise KernelError(
                f"kernel {self.name!r} must be square: got {size} row(s) "
                f"with width(s) {widths}"
            )
        if size % 2 == 0:
            raise KernelError(f"kernel {self.name!r} must be odd-sized, got {size}x{size}")

        for r, row in enumerate(self.rows):
            for c, w in enumerate(row):
                if not WEIGHT_MIN <= w <= WEIGHT_MAX:
                    raise KernelError(
                        f"kernel {self.name!r} weight at ({r},{c}) is {w}, outside the "
                        f"hardware's signed 8-bit range [{WEIGHT_MIN}, {WEIGHT_MAX}]"
                    )

    @property
    def size(self) -> int:
        return len(self.rows)

    @property
    def weight_sum(self) -> int:
        return sum(sum(row) for row in self.rows)

    def hardware_gain(self, drop_bits: int) -> float:
        """DC gain once round_saturate has dropped `drop_bits`.

        The pipeline divides every result by 2**drop_bits (4 bits, so 16, for the
        default 20-bit accumulator into a 16-bit feature). A kernel whose weights
        sum to exactly 2**drop_bits therefore comes out at unity - which is why
        `gaussian_blur` looks right on screen and `box_blur` comes out dim.
        """
        return self.weight_sum / (1 << drop_bits)

    def flat(self) -> list[int]:
        return [w for row in self.rows for w in row]

    def render(self) -> str:
        """Right-aligned text grid, for echoing a kernel back to the user."""
        width = max(len(str(w)) for w in self.flat())
        return "\n".join("  ".join(f"{w:>{width}}" for w in row) for row in self.rows)

    @classmethod
    def parse(cls, text: str, name: str = "custom") -> Self:
        """Build a kernel from free-form text.

        Rows are separated by newlines or semicolons, weights by commas or
        whitespace. Surrounding brackets are ignored, so pasting a Python or
        MATLAB literal works:

            1 0 -1; 2 0 -2; 1 0 -1
            [[1, 0, -1], [2, 0, -2], [1, 0, -1]]
        """
        if not text.strip():
            raise KernelError("no kernel weights given")

        # A closing bracket ends a row, so a pasted nested literal splits the
        # same way an explicit ';' does; opening brackets are just noise.
        cleaned = re.sub(r"[\])]", ";", text.strip())
        cleaned = re.sub(r"[\[(]", " ", cleaned)

        rows: list[tuple[int, ...]] = []
        for line in re.split(r"[;\n]", cleaned):
            tokens = [t for t in re.split(r"[,\s]+", line.strip()) if t]
            if not tokens:
                continue
            try:
                rows.append(tuple(int(t) for t in tokens))
            except ValueError as exc:
                bad = next(t for t in tokens if not _is_int(t))
                raise KernelError(f"{bad!r} is not an integer weight") from exc

        if not rows:
            raise KernelError("no kernel weights given")
        return cls(name=name, rows=tuple(rows))


def _is_int(token: str) -> bool:
    try:
        int(token)
    except ValueError:
        return False
    return True


def _k(name: str, rows: list[list[int]], description: str) -> Kernel:
    return Kernel(name=name, rows=tuple(tuple(r) for r in rows), description=description)


#: The presets offered in the UI, in menu order.
PRESETS: Final[dict[str, Kernel]] = {
    k.name: k
    for k in (
        _k("identity",
           [[0, 0, 0], [0, 16, 0], [0, 0, 0]],
           "Pass-through. Weight 16 cancels the pipeline's >>4, so out == in."),
        _k("sobel_x",
           [[1, 0, -1], [2, 0, -2], [1, 0, -1]],
           "Sobel horizontal gradient - responds to vertical edges."),
        _k("sobel_y",
           [[1, 2, 1], [0, 0, 0], [-1, -2, -1]],
           "Sobel vertical gradient - responds to horizontal edges."),
        _k("prewitt_x",
           [[1, 0, -1], [1, 0, -1], [1, 0, -1]],
           "Prewitt horizontal gradient - unweighted Sobel."),
        _k("prewitt_y",
           [[1, 1, 1], [0, 0, 0], [-1, -1, -1]],
           "Prewitt vertical gradient."),
        _k("laplacian",
           [[0, -1, 0], [-1, 4, -1], [0, -1, 0]],
           "4-neighbour Laplacian - isotropic second derivative."),
        _k("laplacian_8",
           [[-1, -1, -1], [-1, 8, -1], [-1, -1, -1]],
           "8-neighbour Laplacian - includes the diagonals."),
        _k("gaussian_blur",
           [[1, 2, 1], [2, 4, 2], [1, 2, 1]],
           "3x3 Gaussian. Sums to 16, so it is unity gain on this hardware."),
        _k("box_blur",
           [[1, 1, 1], [1, 1, 1], [1, 1, 1]],
           "Mean filter. Sums to 9, so the result comes out at 9/16 brightness."),
        _k("sharpen",
           [[0, -16, 0], [-16, 80, -16], [0, -16, 0]],
           "Unsharp mask, scaled by 16 so the hardware's >>4 lands at unity."),
        _k("emboss",
           [[-16, -16, 0], [-16, 16, 16], [0, 16, 16]],
           "Directional relief, scaled by 16."),
        _k("scharr_x",
           [[3, 0, -3], [10, 0, -10], [3, 0, -3]],
           "Scharr horizontal gradient - better rotational symmetry than Sobel."),
    )
}


def preset(name: str) -> Kernel:
    try:
        return PRESETS[name]
    except KeyError:
        raise KernelError(
            f"unknown preset {name!r}; choose one of: {', '.join(PRESETS)}"
        ) from None


def common_size(kernels: Sequence[Kernel]) -> int:
    """The one window size every kernel in a run shares.

    conv_system has a single WINDOW_SIZE, so a run can mix any kernels as long as
    they are all the same size.
    """
    if not kernels:
        raise KernelError("no kernels given")
    sizes = sorted({kernel.size for kernel in kernels})
    if len(sizes) != 1:
        raise KernelError(
            "all kernels in one run must be the same size, got "
            + ", ".join(f"{size}x{size}" for size in sizes)
        )
    return sizes[0]
