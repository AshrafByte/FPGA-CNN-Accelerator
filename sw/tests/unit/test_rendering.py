"""core.rendering: display normalisation, ASCII previews and PNG grids."""

from __future__ import annotations

import numpy as np
from PIL import Image

from conv_lab.core.images import generate_pattern
from conv_lab.core.rendering import normalise, save_grid, to_ascii


def test_normalise_stretches_signed_features_into_display_range():
    features = np.array([[-1000, 0], [500, 1000]], dtype=np.int32)
    shown = normalise(features)
    assert (shown.min(), shown.max()) == (0, 255)

    flat = normalise(np.zeros((4, 4), dtype=np.int32))
    assert np.all(flat == 128)


def test_shared_normalisation_maps_equal_values_to_equal_pixels():
    reference_frame = np.array([[-48, 0], [0, 48]], dtype=np.int32)
    hardware_frame = reference_frame.copy()
    hardware_frame[0, 0] = -400                          # one stray hardware value
    lo = int(min(reference_frame.min(), hardware_frame.min()))
    hi = int(max(reference_frame.max(), hardware_frame.max()))

    agree = reference_frame == hardware_frame
    assert np.array_equal(normalise(reference_frame, lo, hi)[agree],
                          normalise(hardware_frame, lo, hi)[agree])
    # Normalised separately, that one value would repaint pixels where they agree.
    assert normalise(reference_frame)[0, 1] != normalise(hardware_frame)[0, 1]


def test_ascii_preview_is_rectangular():
    rows = to_ascii(generate_pattern("circle", 32), width=16)
    assert len({len(row) for row in rows}) == 1


def test_save_grid_adds_a_row_per_entry(tmp_path):
    frame = np.zeros((10, 10), dtype=np.uint8)
    small = np.full((8, 8), 255, dtype=np.uint8)
    row = [("input", frame), ("a", small), ("b", small)]
    one = save_grid([row], tmp_path / "one.png")
    two = save_grid([row, row], tmp_path / "two.png")
    with Image.open(one) as a, Image.open(two) as b:
        assert a.width == b.width and b.height > a.height
        assert a.mode == "L"
