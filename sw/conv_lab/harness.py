"""Harness: the run pipeline every front end shares.

One frame goes through the reference model and, when a testbench is attached, the
hardware - then the two are compared. This is the only module that imports both
conv_lab.core.reference and conv_lab.hardware: the two sides of a run meet here
and nowhere else.

The CLI and the hardware regression each own their presentation (flags and
printing on one side, fixtures and asserts on the other) and nothing more. What a
run *does* lives here, so changing it changes both.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from .core.comparison import RunComparison
from .core.images import validate_dimensions
from .core.kernels import Kernel, common_size
from .core.reference import convolve_all, drop_bits
from .hardware import QuestaTestbench, TestbenchError, TestbenchResult


@dataclass(frozen=True, slots=True, eq=False)
class HarnessRun:
    """What one frame produced: the comparison, and the testbench run behind it."""

    comparison: RunComparison
    result: TestbenchResult | None = None     # None when no testbench was attached

    @property
    def simulated(self) -> bool:
        return self.result is not None


class Harness:
    """Runs frames through the reference model and, if attached, a QuestaTestbench.

    Without a testbench this is a reference-only harness: nothing is simulated, so
    nothing can mismatch. With one, the testbench keeps its session state - one
    run directory, one compile - across every frame this harness runs.
    """

    def __init__(self, testbench: QuestaTestbench | None = None) -> None:
        self.testbench = testbench

    def run(self, image: np.ndarray, kernels: Sequence[Kernel]) -> HarnessRun:
        """Validate the inputs, compute the reference, simulate if attached, compare."""
        window = common_size(kernels)
        validate_dimensions(*image.shape, window)
        reference = convolve_all(image, kernels)
        result = None if self.testbench is None else self.testbench.run(image, kernels)
        if result is not None:
            _check_drop(result, window)

        hardware = None if result is None else result.features
        return HarnessRun(RunComparison.build(image, kernels, reference, hardware), result)

    def run_stream(self, frames: Sequence[np.ndarray], kernels: Sequence[Kernel], *,
                   gap: int = 0) -> list[HarnessRun]:
        """Several frames through one simulation with no reset between them.

        Each frame is compared with its own reference, so a pipeline that failed
        to re-arm between frames shows up as a mismatch in the frame it smeared.
        Returns one HarnessRun per frame, in order.
        """
        window = common_size(kernels)
        for frame in frames:
            validate_dimensions(*frame.shape, window)
        references = [convolve_all(frame, kernels) for frame in frames]
        results = (None if self.testbench is None
                   else self.testbench.run_stream(frames, kernels, gap=gap))
        if results:
            _check_drop(results[0], window)

        runs = []
        for index, (frame, reference) in enumerate(zip(frames, references)):
            result = None if results is None else results[index]
            hardware = None if result is None else result.features
            runs.append(HarnessRun(RunComparison.build(frame, kernels, reference, hardware), result))
        return runs


def _check_drop(result: TestbenchResult, window: int) -> None:
    """The hardware's rounding width checked against the model's: a comparison of
    the two sides, so it happens here rather than inside either one."""
    if result.drop_bits != drop_bits(window):
        raise TestbenchError(
            f"hardware reports DROP={result.drop_bits} but the reference model assumes "
            f"{drop_bits(window)} - the models have diverged"
        )
