"""Grayscale frames going in: loading, synthetic patterns, and the geometry rules."""

from __future__ import annotations

from pathlib import Path
from typing import Final, Literal

import numpy as np
from PIL import Image, ImageDraw

MAX_DIMENSION: Final = 512  # a 512x512 frame is already ~10s of simulated stream

PatternName = Literal["ramp", "checker", "circle", "bars", "noise", "edges"]
PATTERNS: Final[tuple[PatternName, ...]] = ("ramp", "checker", "circle", "bars", "noise", "edges")

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


def _random_edges(size: int, seed: int) -> np.ndarray:
    """Edges of random direction, length, curvature and contrast.

    A Voronoi mosaic of irregular cells in random grey levels, overlaid with ellipses,
    polygons and strokes. Unlike checker and bars no edge direction or spacing repeats,
    so every kernel orientation meets edges. Shape counts and sizes scale with the
    frame (the reference design is 128x128), so the density is the same at any size.
    """
    rng = np.random.default_rng(seed)
    scale = size / 128
    area = scale * scale
    seeds = rng.uniform(0, size, size=(max(4, round(34 * area)), 2))
    greys = rng.integers(20, 236, size=len(seeds))
    frame = np.empty((size, size), dtype=np.uint8)
    cols = np.arange(size)
    for r in range(size):  # row by row: never a size x size x cells distance array
        dist = (r - seeds[:, 0]) ** 2 + (cols[:, None] - seeds[:, 1]) ** 2
        frame[r] = greys[np.argmin(dist, axis=1)]

    img = Image.fromarray(frame)
    draw = ImageDraw.Draw(img)
    for _ in range(max(2, round(7 * area))):  # ellipses: curved edges of every slope
        x0, y0 = rng.uniform(-10 * scale, size - 20 * scale, size=2)
        w, h = rng.uniform(12 * scale, 48 * scale, size=2)
        draw.ellipse((x0, y0, x0 + w, y0 + h), fill=int(rng.integers(0, 256)))
    for _ in range(max(1, round(5 * area))):  # triangles and quadrilaterals
        cx, cy = rng.uniform(0, size, size=2)
        corners = int(rng.integers(3, 5))
        points = [(cx + rng.uniform(-22, 22) * scale, cy + rng.uniform(-22, 22) * scale)
                  for _ in range(corners)]
        draw.polygon(points, fill=int(rng.integers(0, 256)))
    for _ in range(max(2, round(9 * area))):  # thin and thick strokes at random angles
        x0, y0, x1, y1 = rng.uniform(0, size, size=4)
        width = max(1, round(int(rng.integers(1, 4)) * scale))
        draw.line((x0, y0, x1, y1), fill=int(rng.integers(0, 256)), width=width)
    return np.asarray(img, dtype=np.uint8)


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
        case "edges":
            frame = _random_edges(size, seed)
        case _:
            raise ImageError(f"unknown pattern {name!r}; choose one of: {', '.join(PATTERNS)}")

    return np.broadcast_to(frame, (size, size)).astype(np.uint8)
