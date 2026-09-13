"""core.reference: the bit-accurate golden model of the conv_system datapath."""

from __future__ import annotations

import numpy as np

from conv_lab.core import reference
from conv_lab.core.images import generate_pattern
from conv_lab.core.kernels import Kernel, preset


def test_identity_kernel_reproduces_the_interior_of_the_frame():
    image = generate_pattern("noise", 12, seed=7)
    out = reference.convolve(image, preset("identity"))
    assert np.array_equal(out, image[1:-1, 1:-1])


def test_round_half_to_even_not_half_away_from_zero():
    # box_blur sums a 3x3 window; a uniform frame of v gives a MAC of 9v, and
    # 9v/16 lands exactly on .5 for v chosen so 9v % 16 == 8.
    for value, expected in ((16, 9), (48, 27)):  # 144/16=9 exact, 432/16=27 exact
        frame = np.full((5, 5), value, dtype=np.uint8)
        assert reference.convolve(frame, preset("box_blur"))[0, 0] == expected

    # 9*80 = 720, 720/16 = 45 exact; 9*81 = 729 -> 45.5625 -> 46 (above the half)
    assert reference.convolve(np.full((5, 5), 81, np.uint8), preset("box_blur"))[0, 0] == 46
    # 9*112 = 1008 -> 63.0 exact
    assert reference.convolve(np.full((5, 5), 112, np.uint8), preset("box_blur"))[0, 0] == 63


def test_ties_round_toward_the_even_quotient():
    # A single tap of 1 with drop=4: MAC == pixel, so the tie cases are pixels
    # ending in 8 -> quotient .5 -> must land on the even neighbour.
    tap = Kernel("single", ((0, 0, 0), (0, 1, 0), (0, 0, 0)))
    for pixel, expected in ((8, 0), (24, 2), (40, 2), (56, 4)):
        frame = np.full((5, 5), pixel, dtype=np.uint8)
        assert reference.convolve(frame, tap)[0, 0] == expected, pixel


def test_the_16_bit_clamp_is_unreachable_for_an_8_bit_pixel_path():
    # DROP == $clog2(K**2), so the worst case is 255 * 128 * K**2 >> $clog2(K**2),
    # which never exceeds 255 * 128 = 32640 < 32767. Confirm the extremes of the
    # legal weight range stay inside the feature width for every supported K.
    limit = (1 << 15) - 1
    for size in (3, 5, 7):
        white = np.full((size + 2, size + 2), 255, dtype=np.uint8)
        for weight in (127, -128):
            hot = Kernel("hot", tuple((weight,) * size for _ in range(size)))
            out = reference.convolve(white, hot)
            assert -limit - 1 < out.min() <= out.max() < limit, (size, weight)


def test_negative_weights_give_negative_features():
    image = generate_pattern("bars", 16)
    out = reference.convolve(image, preset("sobel_x"))
    assert out.min() < 0 < out.max()


def test_output_geometry_is_valid_only():
    image = generate_pattern("ramp", 20)
    assert reference.convolve(image, preset("sobel_x")).shape == (18, 18)


def test_relu_clamps_negatives_and_leaves_the_rest_alone():
    image = generate_pattern("circle", 20)
    raw = reference.convolve(image, preset("sobel_x"))
    rectified = reference.convolve(image, preset("sobel_x"), relu=True)

    assert raw.min() < 0, "sobel_x on a circle should produce negatives to clamp"
    assert rectified.min() == 0
    assert np.array_equal(rectified, np.where(raw > 0, raw, 0))
    assert rectified.dtype == raw.dtype


def test_relu_is_off_by_default():
    image = generate_pattern("bars", 16)
    assert np.array_equal(
        reference.convolve(image, preset("sobel_x")),
        reference.convolve(image, preset("sobel_x"), relu=False),
    )
    assert reference.convolve(image, preset("sobel_x")).min() < 0


def test_accumulator_width_matches_the_rtl():
    assert reference.accumulator_width(3) == 20  # 2*8 + $clog2(9)
    assert reference.drop_bits(3) == 4


def test_convolve_all_stacks_one_frame_per_kernel_like_the_testbench():
    image = generate_pattern("circle", 20)
    kernels = [preset("sobel_x"), preset("gaussian_blur")]
    frames = reference.convolve_all(image, kernels)

    assert frames.shape == (2, 18, 18)
    for index, kernel in enumerate(kernels):
        assert np.array_equal(frames[index], reference.convolve(image, kernel))
