"""Terminal text formatting: rules, kernel cards, stats and ASCII previews."""

from __future__ import annotations

import numpy as np

from ..core.kernels import Kernel
from ..core.rendering import to_ascii

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
    """Render display-ready uint8 frames as labelled ASCII columns, aligned at the top.

    Normalising is the caller's job, because only the caller knows which frames
    must share a scale - see core.rendering.normalise.
    """
    width = width or panel_width(len(panels))
    columns: list[list[str]] = []
    for label, frame in panels.items():
        art = to_ascii(frame, width=width)
        rendered = max((len(line) for line in art), default=width)
        header = f"{label} ({frame.shape[1]}x{frame.shape[0]})"
        columns.append([header.center(rendered), *[line.ljust(rendered) for line in art]])

    height = max(len(col) for col in columns)
    for col in columns:
        col += [" " * len(col[0])] * (height - len(col))

    separator = " " * PANEL_GAP
    return "\n".join(separator.join(parts) for parts in zip(*columns, strict=True))


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
