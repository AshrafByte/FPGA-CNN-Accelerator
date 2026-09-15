"""Host-side test of the PYNQ driver (fpga/board/pynq/conv_demo.py), no board needed.

ConvAccelerator is run against FakeConvAxiLite, a register-level model of
fpga/board/rtl/conv_axi_lite.sv + conv_system: the same register map, a weight
shift register per lane, the hardware tap order (a new window column enters at
index 0), round half up, frame-done set by the frame's last feature and cleared
by the next frame's first pixel, FRAME_COUNT, and one soft reset clearing
everything. The model computes the features the RTL would, independently of the
driver's golden model, so a driver that sent a kernel in the wrong order, reset
between frames, or rewrote an unchanged kernel fails here.

    python -m pytest fpga/board/tests          # or: python fpga/board/tests/test_conv_demo_driver.py
"""

from __future__ import annotations

import sys
import types
from pathlib import Path

import numpy as np
import pytest

PYNQ_DIR = Path(__file__).resolve().parents[1] / "pynq"
sys.path.insert(0, str(PYNQ_DIR))

import conv_demo  # noqa: E402

REG = conv_demo.REG


class FakeConvAxiLite:
    """conv_axi_lite + conv_system at register level."""

    def __init__(self, input_size=32, window=3, lanes=1, relu=False):
        self.w, self.n, self.k, self.relu = input_size, window, lanes, relu
        self.out = input_size - window + 1
        self.idx_bits = int(np.ceil(np.log2(self.out * self.out)))
        self.ctrl_writes = []
        self.weight_writes = 0
        self._reset()

    # -- state ------------------------------------------------------------------------
    def _reset(self):
        self.weights = [[0] * (self.n * self.n) for _ in range(self.k)]
        self.kernel_sel = 0
        self.weight_count = 0
        self.pixels = []
        self.done = False
        self.frame_count = 0
        self.features = np.zeros((self.k, self.out * self.out), dtype=np.int64)

    def _pixel(self, value):
        if self.done:                       # the next frame's first pixel clears the done flag
            self.done = False
            self.pixels = []
        self.pixels.append(value & 0xFF)
        if len(self.pixels) == self.w * self.w:
            self._convolve()
            self.done = True
            self.frame_count += 1

    def _convolve(self):
        image = np.array(self.pixels, dtype=np.int64).reshape(self.w, self.w)
        n, drop = self.n, (self.n * self.n - 1).bit_length()
        for lane in range(self.k):
            taps = [((w + 128) % 256) - 128 for w in self.weights[lane]]   # int8
            for r in range(self.out):
                for c in range(self.out):
                    acc = sum(int(image[r + kr, c + (n - 1 - kc)]) * taps[kr * n + kc]
                              for kr in range(n) for kc in range(n))
                    if drop:
                        acc = (acc + (1 << (drop - 1))) >> drop
                    acc = max(-32768, min(32767, acc))
                    if self.relu:
                        acc = max(acc, 0)
                    self.features[lane, r * self.out + c] = acc

    # -- MMIO -------------------------------------------------------------------------
    def write(self, offset, value):
        value &= 0xFFFFFFFF
        if offset == REG["CTRL"]:
            self.ctrl_writes.append(value)
            if value & 1:
                self._reset()
        elif offset == REG["KERNEL_SEL"]:
            self.kernel_sel = value
        elif offset == REG["WEIGHT"]:
            lane = self.weights[self.kernel_sel]
            lane.pop(0)
            lane.append(value & 0xFF)          # shift register: first weight ends at index 0
            self.weight_count += 1
            self.weight_writes += 1
        elif offset == REG["PIXEL"]:
            self._pixel(value)
        elif offset == REG["PIXELS4"]:
            for b in range(4):
                self._pixel(value >> (8 * b))
        else:
            raise AssertionError("write to unexpected offset 0x%X" % offset)

    def read(self, offset):
        if offset >= conv_demo.FEATURE_BASE:
            local = offset - conv_demo.FEATURE_BASE
            lane, idx = local >> (self.idx_bits + 2), (local >> 2) & ((1 << self.idx_bits) - 1)
            return int(self.features[lane, idx]) & 0xFFFFFFFF
        return {
            REG["ID"]: conv_demo.CORE_ID,
            REG["GEOMETRY"]: (self.k << 24) | (self.n << 16) | self.w,
            REG["FORMAT"]: (int(self.relu) << 16) | (self.idx_bits << 8) | 16,
            REG["STATUS"]: (int(self.done) << 2) | (int(bool(self.pixels) and not self.done) << 1)
                           | int(self.weight_count >= self.n * self.n * self.k),
            REG["WEIGHT_COUNT"]: self.weight_count,
            REG["PIXEL_COUNT"]: len(self.pixels),
            REG["OUT_COUNT"]: self.out * self.out if self.done else 0,
            REG["LATENCY"]: 173,
            REG["FRAME_CYCLES"]: 1072,
            REG["FRAME_COUNT"]: self.frame_count,
        }[offset]


@pytest.fixture
def board(monkeypatch):
    """Install a fake `pynq` module whose MMIO is the register model."""
    def make(**geometry):
        fake = FakeConvAxiLite(**geometry)
        module = types.ModuleType("pynq")
        module.MMIO = lambda base, size: fake
        module.Overlay = lambda path, download=True: object()
        monkeypatch.setitem(sys.modules, "pynq", module)
        return fake, conv_demo.ConvAccelerator(bitfile="conv_demo.bit")
    return make


def test_frames_stream_without_reset_and_match_the_hardware_model(board):
    fake, accel = board()
    kernel = conv_demo.DEMO_KERNELS["sobel_x"]
    for count, name in enumerate(("bars", "checker", "circle", "noise"), start=1):
        image = conv_demo.pattern(name, accel.input_size, seed=count)
        hw, stats = accel.run(image, [kernel])
        assert np.array_equal(hw[0], conv_demo.reference(image, kernel)), name
        assert stats["frames_since_reset"] == count
    assert fake.ctrl_writes == [1, 0], "the driver must reset once, when the overlay opens"
    assert fake.weight_writes == 9, "an unchanged kernel must not be rewritten"


def test_a_new_kernel_is_written_between_frames_without_reset(board):
    fake, accel = board()
    image = conv_demo.pattern("circle", accel.input_size)
    for name in ("sobel_x", "sobel_y", "laplacian", "sobel_y"):
        hw, _ = accel.run(image, [conv_demo.DEMO_KERNELS[name]])
        assert np.array_equal(hw[0], conv_demo.reference(image, conv_demo.DEMO_KERNELS[name])), name
    assert fake.ctrl_writes == [1, 0]
    assert fake.weight_writes == 4 * 9


def test_asymmetric_kernels_need_the_hardware_tap_order(board):
    """sobel_x differs from its column mirror, so a missing row reversal would fail."""
    _, accel = board()
    image = conv_demo.pattern("noise", accel.input_size, seed=7)
    kernel = [[1, 2, 3], [-4, 5, -6], [7, -8, 9]]
    hw, _ = accel.run(image, [kernel])
    assert np.array_equal(hw[0], conv_demo.reference(image, kernel))


def test_two_lanes_and_relu_and_explicit_reset(board):
    fake, accel = board(input_size=16, window=5, lanes=2, relu=True)
    rng = np.random.RandomState(3)
    kernels = [rng.randint(-128, 128, (5, 5)), rng.randint(-128, 128, (5, 5))]
    image = conv_demo.pattern("noise", 16, seed=5)
    hw, stats = accel.run(image, kernels)
    for lane in range(2):
        assert np.array_equal(hw[lane], conv_demo.reference(image, kernels[lane], relu=True))
    accel.reset()
    assert fake.frame_count == 0 and fake.weight_count == 0
    hw, stats = accel.run(image, kernels)                  # kernels reloaded after the reset
    assert stats["frames_since_reset"] == 1
    assert fake.weight_writes == 2 * 2 * 25


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q"]))
