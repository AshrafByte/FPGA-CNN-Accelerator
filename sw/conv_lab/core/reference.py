"""Bit-accurate software model of the conv_system datapath.

This is the golden reference the hardware's output is checked against. It has to
reproduce three things exactly, none of which is plain 2D convolution:

  * a signed multiply-accumulate over a valid-only (no padding) window, so the
    output is (N - K + 1) square;
  * round_saturate's round-half-UP on the drop of ACCUM_WIDTH-FEATURE_WIDTH low
    bits, i.e. floor((MAC + 2**(DROP-1)) / 2**DROP): an exact .5 tie always goes
    toward +infinity (4.5 -> 5, -4.5 -> -4) - not truncation, not
    round-half-to-even, and not round-half-away-from-zero;
  * saturation into the signed FEATURE_WIDTH range.

The clamp is modelled but, for this parameterisation, unreachable. DROP is
$clog2(K**2), so the worst case is 255 * 128 * K**2 >> $clog2(K**2), which is at
most 255 * 128 = 32640 - inside the 16-bit signed range for every odd K. An
8-bit pixel path through this pipeline cannot saturate; the clamp only earns its
keep if PIXEL_WIDTH or FEATURE_WIDTH changes.

The tap-order quirk described in conv_image_tb lives in
`hardware.contract.pack_kernel`, not here: by the time a kernel reaches this
model it is in natural row-major order and the model computes an ordinary
correlation with it.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Final

import numpy as np

from .kernels import Kernel

PIXEL_WIDTH: Final = 8
FEATURE_WIDTH: Final = 16


def accumulator_width(window: int) -> int:
    """conv_system: ACCUM_WIDTH = 2*PIXEL_WIDTH + $clog2(WINDOW_SIZE**2)."""
    return 2 * PIXEL_WIDTH + (window * window - 1).bit_length()


def drop_bits(window: int) -> int:
    """Low bits round_saturate discards, i.e. the pipeline's built-in >>N."""
    return max(accumulator_width(window) - FEATURE_WIDTH, 0)


def convolve(image: np.ndarray, kernel: Kernel, *, relu: bool = False) -> np.ndarray:
    """Golden model: what the hardware must produce for this image and kernel.

    Returns an int32 array of shape (N-K+1, N-K+1) holding signed feature values
    already rounded and saturated to FEATURE_WIDTH bits.

    `relu` appends the activation that would follow this layer in a CNN. It is
    OFF by default and is NOT part of the hardware contract - conv_system has no
    activation stage, so a rectified frame is a layer-level result, not
    something the RTL can be checked against. See `apply_relu`.
    """
    mac = _valid_correlate(image, np.array(kernel.rows, dtype=np.int64))
    features = _round_saturate(mac, drop_bits(kernel.size))
    return apply_relu(features) if relu else features


def apply_relu(features: np.ndarray) -> np.ndarray:
    """max(0, x) - the activation a conv layer is normally followed by.

    This is where the sign that conv_system carefully preserves gets discarded:
    the signed feature bus exists so a downstream stage can make this decision,
    not so the convolution can make it early.
    """
    return np.maximum(features, 0)


def convolve_all(image: np.ndarray, kernels: Sequence[Kernel], *, relu: bool = False) -> np.ndarray:
    """One golden frame per kernel, stacked as (len(kernels), N-K+1, N-K+1).

    The same shape `QuestaTestbench.run` returns, so hardware and reference compare
    lane for lane.
    """
    return np.stack([convolve(image, kernel, relu=relu) for kernel in kernels])


def _valid_correlate(image: np.ndarray, weights: np.ndarray) -> np.ndarray:
    """Sum over every K x K window: out[r,c] = sum image[r+kr, c+kc] * w[kr,kc]."""
    n = image.shape[0]
    k = weights.shape[0]
    out_size = n - k + 1
    source = image.astype(np.int64)

    acc = np.zeros((out_size, out_size), dtype=np.int64)
    for kr in range(k):
        for kc in range(k):
            acc += source[kr : kr + out_size, kc : kc + out_size] * weights[kr, kc]
    return acc


def _round_saturate(values: np.ndarray, drop: int) -> np.ndarray:
    """round_saturate: round half up on values / 2**drop, then clamp.

    The RTL keeps the truncated value and the guard bit (the first discarded bit,
    remainder >= half) and adds the guard bit: floor((x + 2**(drop-1)) / 2**drop).
    """
    if drop > 0:
        quotient = values >> drop                     # floor, toward -inf
        remainder = values - (quotient << drop)       # exact, always 0..2**drop-1
        half = 1 << (drop - 1)
        values = quotient + (remainder >= half)       # tie -> up
    limit = 1 << (FEATURE_WIDTH - 1)
    return np.clip(values, -limit, limit - 1).astype(np.int32)
