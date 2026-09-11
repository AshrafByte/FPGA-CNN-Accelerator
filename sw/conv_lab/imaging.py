"""Grayscale image input and rendering."""

from __future__ import annotations

from pathlib import Path
from typing import Final, Literal

import numpy as np
from PIL import Image

MAX_DIMENSION: Final = 512  # a 512x512 frame is already ~10s of simulated stream

PatternName = Literal["ramp", "checker", "circle", "bars", "noise"]
PATTERNS: Final[tuple[PatternName, ...]] = ("ramp", "checker", "circle", "bars", "noise")


class ImageError(ValueError):
    """An image could not be loaded, or has dimensions the hardware cannot take."""


def validate_dimensions(height: int, width: int, window: int) -> None:
    """Reject geometries conv_system cannot be elaborated for.

    The hardware is square-only (one INPUT_SIZE parameter feeds both the line
    buffer length and the frame geometry), and its output FIFO is sized
    (INPUT_SIZE - WINDOW_SIZE) * (WINDOW_SIZE - 1), which has to be at least 1.
    """
    if height != width:
        raise ImageError(f"the accelerator only takes square frames, got {width}x{height}")
    if height <= window:
        raise ImageError(
            f"a {height}x{width} frame is too small for a {window}x{window} kernel; "
            f"need at least {window + 1}x{window + 1}"
        )
    if height > MAX_DIMENSION:
        raise ImageError(
            f"{width}x{height} exceeds the {MAX_DIMENSION}x{MAX_DIMENSION} cap "
            "(simulation time grows with the pixel count)"
        )


def load_image(path: str | Path, size: int) -> np.ndarray:
    """Load any image as a single-channel uint8 frame, resized to `size`x`size`."""
    path = Path(path)
    if not path.is_file():
        raise ImageError(f"no such image file: {path}")
    try:
        with Image.open(path) as img:
            gray = img.convert("L").resize((size, size), Image.LANCZOS)
    except OSError as exc:
        raise ImageError(f"cannot read {path}: {exc}") from exc
    return np.asarray(gray, dtype=np.uint8)


def generate_pattern(name: PatternName, size: int, *, seed: int = 0) -> np.ndarray:
    """Synthetic test frames, for when the point is the hardware and not the picture."""
    rows, cols = np.ogrid[0:size, 0:size]

    match name:
        case "ramp":
            frame = (rows * size + cols) * 255 // max(size * size - 1, 1)
        case "checker":
            tile = max(size // 8, 1)
            frame = np.where((rows // tile + cols // tile) % 2 == 0, 230, 25)
        case "circle":
            centre = (size - 1) / 2
            radius = size / 3
            dist = np.hypot(rows - centre, cols - centre)
            frame = np.where(dist <= radius, 220, 30)
        case "bars":
            bar = max(size // 8, 1)
            frame = np.where((cols // bar) % 2 == 0, 240, 15) + np.zeros_like(rows)
        case "noise":
            frame = np.random.default_rng(seed).integers(0, 256, size=(size, size))
        case _:
            raise ImageError(f"unknown pattern {name!r}; choose one of: {', '.join(PATTERNS)}")

    return np.broadcast_to(frame, (size, size)).astype(np.uint8)


def normalise(features: np.ndarray) -> np.ndarray:
    """Map signed feature values onto 0..255 for display.

    Edge kernels produce negatives that would otherwise clip to black, so the
    full observed range is stretched rather than simply clamped. A flat result
    (a uniform frame through a zero-sum kernel) maps to mid-grey.
    """
    lo, hi = int(features.min()), int(features.max())
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


def save_comparison(
    source: np.ndarray,
    outputs: dict[str, np.ndarray],
    path: str | Path,
    *,
    scale: int = 4,
    gap: int = 8,
) -> Path:
    """Write input and every output side by side as one PNG.

    Panels are nearest-neighbour upscaled so individual pixels stay visible, and
    the (smaller) output panels are top-aligned against the input.
    """
    panels = [np.kron(p, np.ones((scale, scale), dtype=np.uint8))
              for p in (source, *outputs.values())]

    height = max(p.shape[0] for p in panels)
    width = sum(p.shape[1] for p in panels) + gap * (len(panels) - 1)
    canvas = np.full((height, width), 255, dtype=np.uint8)

    x = 0
    for panel in panels:
        canvas[: panel.shape[0], x : x + panel.shape[1]] = panel
        x += panel.shape[1] + gap

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(canvas, mode="L").save(path)
    return path
