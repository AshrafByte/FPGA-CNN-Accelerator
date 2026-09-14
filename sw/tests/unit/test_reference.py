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


SUM9 = Kernel("sum9", ((1, 1, 1), (1, 1, 1), (1, 1, 1)))
NEG_SUM9 = Kernel("neg_sum9", ((-1, -1, -1), (-1, -1, -1), (-1, -1, -1)))


def test_non_ties_round_to_the_nearest_value():
    # A uniform frame of v through nine +-1 taps gives MAC = +-9v, and drop = 4
    # divides by 16. Away from .5 every rounding mode agrees on the nearest value.
    cases = (
        (16, 9, -9),     # 144/16 = 9 exact
        (112, 63, -63),  # 1008/16 = 63 exact
        (81, 46, -46),   # 729/16 = 45.5625, above the half
        (82, 46, -46),   # 738/16 = 46.125, below the half
    )
    for value, positive, negative in cases:
        frame = np.full((5, 5), value, dtype=np.uint8)
        assert reference.convolve(frame, SUM9)[0, 0] == positive, value
        assert reference.convolve(frame, NEG_SUM9)[0, 0] == negative, value


def test_ties_round_half_up_toward_plus_infinity():
    # A single centre tap of +-1 with drop = 4: MAC == +-pixel, so a pixel
    # ending in 8 (mod 16) puts the quotient exactly on .5. Round half up sends
    # every tie toward +infinity: 4.5 -> 5 (half-to-even would give 4) and
    # -4.5 -> -4 (half-away-from-zero would give -5).
    plus = Kernel("plus1", ((0, 0, 0), (0, 1, 0), (0, 0, 0)))
    minus = Kernel("minus1", ((0, 0, 0), (0, -1, 0), (0, 0, 0)))
    for pixel, positive, negative in ((8, 1, 0), (24, 2, -1), (40, 3, -2),
                                      (56, 4, -3), (72, 5, -4)):
        frame = np.full((5, 5), pixel, dtype=np.uint8)
        assert reference.convolve(frame, plus)[0, 0] == positive, pixel
        assert reference.convolve(frame, minus)[0, 0] == negative, pixel


def test_rounding_is_floor_of_value_plus_half_for_every_20_bit_accumulator():
    # Every value a 3x3 accumulator can hold, against the RTL's definition
    # floor((x + 2**(DROP-1)) / 2**DROP), clamped to 16 bits.
    drop = reference.drop_bits(3)
    values = np.arange(-(1 << 19), 1 << 19, dtype=np.int64)
    expected = np.clip((values + (1 << (drop - 1))) >> drop, -(1 << 15), (1 << 15) - 1)
    assert np.array_equal(reference._round_saturate(values, drop), expected)


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
