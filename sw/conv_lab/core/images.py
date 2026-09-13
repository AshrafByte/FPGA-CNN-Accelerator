"""Grayscale frames going in: loading, synthetic patterns, and the geometry rules."""

from __future__ import annotations

from pathlib import Path
from typing import Final, Literal

import numpy as np
from PIL import Image

MAX_DIMENSION: Final = 512  # a 512x512 frame is already ~10s of simulated stream

PatternName = Literal["ramp", "checker", "circle", "bars", "noise"]
PATTERNS: Final[tuple[PatternName, ...]] = ("ramp", "checker", "circle", "bars", "noise")

#: Checker tiles and bars are never narrower than this. At 2 px - what size // 8
#: gives a 16x16 frame - every 3x3 window straddles an edge, so an edge kernel
#: returns a re-signed copy of the pattern instead of showing where its edges are.
MIN_FEATURE_PX: Final = 4


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
            tile = max(size // 8, MIN_FEATURE_PX)
            frame = np.where((rows // tile + cols // tile) % 2 == 0, 230, 25)
        case "circle":
            centre = (size - 1) / 2
            radius = size / 3
            dist = np.hypot(rows - centre, cols - centre)
            frame = np.where(dist <= radius, 220, 30)
        case "bars":
            bar = max(size // 8, MIN_FEATURE_PX)
            frame = np.where((cols // bar) % 2 == 0, 240, 15) + np.zeros_like(rows)
        case "noise":
            frame = np.random.default_rng(seed).integers(0, 256, size=(size, size))
        case _:
            raise ImageError(f"unknown pattern {name!r}; choose one of: {', '.join(PATTERNS)}")

    return np.broadcast_to(frame, (size, size)).astype(np.uint8)
