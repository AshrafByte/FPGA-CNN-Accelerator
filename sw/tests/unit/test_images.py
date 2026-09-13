"""core.images: synthetic patterns and the geometry conv_system can take."""

from __future__ import annotations

import numpy as np
import pytest

from conv_lab.core.images import PATTERNS, ImageError, generate_pattern, validate_dimensions


@pytest.mark.parametrize(
    ("height", "width", "message"),
    [
        (32, 64, "square"),
        (3, 3, "too small"),
        (4096, 4096, "exceeds"),
    ],
)
def test_bad_geometry_is_rejected(height, width, message):
    with pytest.raises(ImageError, match=message):
        validate_dimensions(height, width, 3)


def test_smallest_legal_frame_is_accepted():
    validate_dimensions(4, 4, 3)


def test_patterns_are_single_channel_uint8():
    for name in PATTERNS:
        frame = generate_pattern(name, 16)
        assert frame.shape == (16, 16)
        assert frame.dtype == np.uint8
