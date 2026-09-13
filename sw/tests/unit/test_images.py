"""core.images: synthetic patterns and the geometry conv_system can take."""

from __future__ import annotations

import numpy as np
import pytest

from conv_lab.core import reference
from conv_lab.core.images import PATTERNS, ImageError, generate_pattern, validate_dimensions
from conv_lab.core.kernels import preset


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


@pytest.mark.parametrize("size", [8, 16, 32, 64])
@pytest.mark.parametrize("pattern", ["checker", "bars"])
def test_patterns_are_coarse_enough_for_an_edge_kernel_to_find_edges(pattern, size):
    """With tiles narrower than the 3x3 window every window straddles an edge, and an
    edge kernel returns a re-signed copy of the pattern: no feature is ever zero. That
    is what the 16x16 checker used to do."""
    out = reference.convolve(generate_pattern(pattern, size), preset("sobel_x"))
    assert (out == 0).any(), "no flat region survived: the pattern is finer than the kernel"
