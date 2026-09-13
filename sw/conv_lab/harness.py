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

        # The hardware's rounding width checked against the model's: a comparison
        # of the two sides, so it happens here rather than inside either one.
        if result is not None and result.drop_bits != drop_bits(window):
            raise TestbenchError(
                f"hardware reports DROP={result.drop_bits} but the reference model assumes "
                f"{drop_bits(window)} - the models have diverged"
            )

        hardware = None if result is None else result.features
        return HarnessRun(RunComparison.build(image, kernels, reference, hardware), result)
