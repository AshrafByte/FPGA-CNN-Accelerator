"""harness: the run pipeline both front ends share, and where the two sides meet."""

from __future__ import annotations

import dataclasses
from pathlib import Path

import numpy as np
import pytest

from conv_lab.core import reference
from conv_lab.core.images import generate_pattern
from conv_lab.core.kernels import Kernel, KernelError, preset
from conv_lab.hardware import TestbenchError, TestbenchResult
from conv_lab.harness import Harness


class _FakeTestbench:
    """Stands in for QuestaTestbench: returns the reference frames, optionally corrupted."""

    def __init__(self, corrupt: bool = False):
        self.corrupt = corrupt
        self.calls = 0

    def run(self, image, kernels):
        self.calls += 1
        features = reference.convolve_all(image, kernels)
        if self.corrupt:
            features[0, 0, 0] += 1
        return TestbenchResult(features=features, drop_bits=4, elapsed_s=0.0,
                               run_dir=Path("."), log="STATUS: OK")


def test_a_reference_only_harness_simulates_nothing():
    image = generate_pattern("circle", 16)
    run = Harness().run(image, [preset("sobel_x"), preset("gaussian_blur")])

    assert not run.simulated and run.result is None
    assert all(lane.verdict is None for lane in run.comparison.lanes)
    assert np.array_equal(run.comparison.lanes[1].reference,
                          reference.convolve(image, preset("gaussian_blur")))


def test_a_harness_with_a_testbench_compares_what_it_simulated():
    image = generate_pattern("noise", 12, seed=4)
    kernels = [preset("sobel_x"), preset("laplacian")]

    clean = Harness(_FakeTestbench()).run(image, kernels)
    assert clean.simulated and clean.comparison.all_match

    broken = Harness(_FakeTestbench(corrupt=True)).run(image, kernels)
    assert [lane.kernel.name for lane in broken.comparison.mismatched] == ["sobel_x"]


def test_mixed_kernel_sizes_are_rejected_before_anything_runs():
    bench = _FakeTestbench()
    five = Kernel("five", tuple((1,) * 5 for _ in range(5)))
    with pytest.raises(KernelError, match="3x3, 5x5"):
        Harness(bench).run(generate_pattern("ramp", 16), [preset("sobel_x"), five])
    assert bench.calls == 0


def test_a_rounding_width_the_reference_does_not_expect_is_reported():
    """The DROP check compares the two sides, so it belongs to the harness."""
    class WrongDrop(_FakeTestbench):
        def run(self, image, kernels):
            return dataclasses.replace(super().run(image, kernels), drop_bits=5)

    with pytest.raises(TestbenchError, match="DROP=5"):
        Harness(WrongDrop()).run(generate_pattern("ramp", 8), [preset("identity")])
