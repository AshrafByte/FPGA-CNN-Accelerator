"""core.kernels: presets, parsing custom weights, and the one-size-per-run rule."""

from __future__ import annotations

import pytest

from conv_lab.core.kernels import PRESETS, Kernel, KernelError, common_size, preset
from conv_lab.core.reference import drop_bits


def test_every_preset_is_loadable_by_the_hardware():
    for name, kernel in PRESETS.items():
        assert kernel.name == name
        assert kernel.size % 2 == 1
        assert all(-128 <= w <= 127 for w in kernel.flat())


def test_unity_gain_presets_really_are_unity():
    drop = drop_bits(3)
    for name in ("identity", "gaussian_blur", "sharpen", "emboss"):
        assert PRESETS[name].hardware_gain(drop) == 1.0


@pytest.mark.parametrize(
    "text",
    [
        "1 0 -1; 2 0 -2; 1 0 -1",
        "1,0,-1\n2,0,-2\n1,0,-1",
        "[[1, 0, -1], [2, 0, -2], [1, 0, -1]]",
    ],
)
def test_parse_accepts_the_usual_ways_of_typing_a_matrix(text):
    assert Kernel.parse(text).rows == PRESETS["sobel_x"].rows


@pytest.mark.parametrize(
    ("text", "message"),
    [
        ("1 2; 3 4", "odd-sized"),
        ("1 2 3; 4 5", "square"),
        ("1 2 3; 4 x 6; 7 8 9", "not an integer"),
        ("", "no kernel weights"),
        ("200 0 0; 0 0 0; 0 0 0", "signed 8-bit"),
    ],
)
def test_malformed_kernels_are_rejected_with_a_useful_message(text, message):
    with pytest.raises(KernelError, match=message):
        Kernel.parse(text)


def test_unknown_preset_lists_the_alternatives():
    with pytest.raises(KernelError, match="sobel_x"):
        preset("sobel_diagonal")


def test_common_size_names_every_size_it_found():
    five = Kernel("five", tuple((1,) * 5 for _ in range(5)))
    assert common_size([preset("sobel_x"), preset("laplacian")]) == 3
    with pytest.raises(KernelError, match="3x3, 5x5"):
        common_size([preset("sobel_x"), five])
    with pytest.raises(KernelError, match="no kernels"):
        common_size([])
