"""Terminal presentation: side-by-side previews, stats, and the hardware-vs-model verdict."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .imaging import normalise, to_ascii
from .kernels import Kernel

RULE_WIDTH = 78
PANEL_GAP = 3
#: Widest line the previews may occupy. Panels shrink to share it.
TOTAL_WIDTH = 150


def rule(title: str = "", width: int = RULE_WIDTH) -> str:
    if not title:
        return "-" * width
    return f"-- {title} " + "-" * max(width - len(title) - 4, 0)


def panel_width(count: int, total: int = TOTAL_WIDTH) -> int:
    """Pixels per preview panel so `count` of them fit across the terminal.

    to_ascii spends two characters per pixel to keep the aspect ratio, hence
    the halving.
    """
    budget = (total - PANEL_GAP * (count - 1)) // count
    return max(budget // 2, 8)


def side_by_side(panels: dict[str, np.ndarray], width: int | None = None) -> str:
    """Render several frames as labelled ASCII columns, aligned at the top.

    Frames are normalised independently: the output of an edge kernel is signed
    and would otherwise be almost entirely black next to its input.
    """
    width = width or panel_width(len(panels))
    columns: list[list[str]] = []
    for label, frame in panels.items():
        art = to_ascii(normalise(frame), width=width)
        rendered = max((len(line) for line in art), default=width)
        header = f"{label} ({frame.shape[1]}x{frame.shape[0]})"
        columns.append([header.center(rendered), *[line.ljust(rendered) for line in art]])

    height = max(len(col) for col in columns)
    for col in columns:
        col += [" " * len(col[0])] * (height - len(col))

    separator = " " * PANEL_GAP
    return "\n".join(separator.join(parts) for parts in zip(*columns, strict=True))


@dataclass(frozen=True, slots=True)
class Comparison:
    """How the hardware's frame compares to the golden model's."""

    total: int
    mismatches: int
    max_abs_error: int
    first_mismatch: tuple[int, int] | None

    @property
    def exact(self) -> bool:
        return self.mismatches == 0

    def summary(self) -> str:
        if self.exact:
            return f"MATCH      all {self.total} feature(s) bit-exact against the golden model"
        row, col = self.first_mismatch or (-1, -1)
        return (
            f"MISMATCH   {self.mismatches}/{self.total} feature(s) differ, "
            f"max |error| {self.max_abs_error}, first at row {row} col {col}"
        )


def compare(hardware: np.ndarray, golden: np.ndarray) -> Comparison:
    diff = hardware.astype(np.int64) - golden.astype(np.int64)
    wrong = np.flatnonzero(diff.ravel())
    first = np.unravel_index(int(wrong[0]), diff.shape) if wrong.size else None
    return Comparison(
        total=int(diff.size),
        mismatches=int(wrong.size),
        max_abs_error=int(np.abs(diff).max()) if diff.size else 0,
        first_mismatch=(int(first[0]), int(first[1])) if first else None,
    )


def kernel_card(kernel: Kernel, drop: int) -> str:
    """The kernel, its description, and what the pipeline's >>N does to its gain."""
    gain = kernel.hardware_gain(drop)
    lines = [f"kernel: {kernel.name}  ({kernel.size}x{kernel.size})"]
    if kernel.description:
        lines.append(f"        {kernel.description}")
    lines.append("")
    lines += [f"        {row}" for row in kernel.render().splitlines()]
    lines.append("")
    lines.append(
        f"        weight sum {kernel.weight_sum}, hardware >>{drop} "
        f"=> DC gain {gain:.3f}"
        + ("  (unity)" if abs(gain - 1.0) < 1e-9 else "")
    )
    return "\n".join(lines)


def stats(features: np.ndarray) -> str:
    return (
        f"min {int(features.min()):>7}   max {int(features.max()):>7}   "
        f"mean {features.mean():>9.2f}   nonzero {int(np.count_nonzero(features))}/{features.size}"
    )
