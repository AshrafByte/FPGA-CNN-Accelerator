"""Frames going out: display normalisation, ASCII previews and labelled PNG grids."""

from __future__ import annotations

from collections.abc import Sequence
from pathlib import Path
from typing import Final

import numpy as np
from PIL import Image, ImageDraw, ImageFont

MIN_PANEL_PX: Final = 200   # PNG panels are upscaled to at least this, so labels fit
LABEL_PX: Final = 12


def normalise(features: np.ndarray, lo: int | None = None, hi: int | None = None) -> np.ndarray:
    """Map signed feature values onto 0..255 for display.

    Edge kernels produce negatives that would otherwise clip to black, so the
    full observed range is stretched rather than simply clamped. A flat result
    (a uniform frame through a zero-sum kernel) maps to mid-grey.

    Frames being compared must share `lo`/`hi`. Normalised independently, one
    stray value in one frame rescales that whole panel, so regions where the
    frames agree stop looking alike - or frames that disagree start to.
    """
    lo = int(features.min()) if lo is None else lo
    hi = int(features.max()) if hi is None else hi
    if hi == lo:
        return np.full(features.shape, 128, dtype=np.uint8)
    scaled = (features.astype(np.float64) - lo) * (255.0 / (hi - lo))
    return scaled.round().clip(0, 255).astype(np.uint8)


_RAMP: Final = " .:-=+*#%@"


def to_ascii(frame: np.ndarray, width: int = 48) -> list[str]:
    """Render a uint8 frame as ASCII rows, nearest-neighbour downsampled.

    Two characters per pixel, so the result keeps roughly square proportions in
    a terminal.
    """
    height, source_width = frame.shape
    width = min(width, source_width)
    height_out = max(round(height * width / source_width / 2), 1)

    col_idx = (np.arange(width) * source_width // width).clip(0, source_width - 1)
    row_idx = (np.arange(height_out) * height // height_out).clip(0, height - 1)
    sampled = frame[np.ix_(row_idx, col_idx)]

    levels = (sampled.astype(np.uint16) * (len(_RAMP) - 1) // 255).clip(0, len(_RAMP) - 1)
    return ["".join(_RAMP[v] * 2 for v in row) for row in levels]


def save_grid(
    rows: Sequence[Sequence[tuple[str, np.ndarray]]],
    path: str | Path,
    *,
    gap: int = 8,
) -> Path:
    """Write labelled uint8 panels as a PNG, one row of panels per entry.

    Every cell has the footprint of the largest panel, so columns line up across
    rows and the N-K+1 outputs sit top-left beside their N x N input. Panels are
    nearest-neighbour upscaled, keeping pixels visible, until at least
    MIN_PANEL_PX wide so the labels fit.
    """
    side = max(max(frame.shape) for row in rows for _, frame in row)
    scale = -(-MIN_PANEL_PX // side)                 # ceiling division
    label_h = LABEL_PX + 6
    cell_w, cell_h = side * scale, side * scale + label_h
    columns = max(len(row) for row in rows)

    canvas = Image.new("L", (columns * (cell_w + gap) + gap, len(rows) * (cell_h + gap) + gap), 255)
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default(size=LABEL_PX)

    for r, row in enumerate(rows):
        y = gap + r * (cell_h + gap)
        for c, (label, frame) in enumerate(row):
            x = gap + c * (cell_w + gap)
            draw.text((x, y), label, fill=0, font=font)
            panel = np.kron(frame, np.ones((scale, scale), dtype=np.uint8))
            canvas.paste(Image.fromarray(panel), (x, y + label_h))

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)
    return path
