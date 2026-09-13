"""conv_lab - run images through conv_system's SystemVerilog testbench and a Python
reference model, and compare the two.

The folders are the architecture. Each layer may only import the layers above it:

    core/        pure Python: kernels, images, reference model, comparison, rendering
    hardware/    the only package that knows QuestaSim and conv_image_tb
    harness.py   Harness - the pipeline every front end uses, and the only module
                 where the hardware side and the reference side meet
    cli/         the command-line front end

tests/unit/test_architecture.py enforces that order.
"""

from .core.comparison import LaneComparison, RunComparison, Verdict
from .core.images import ImageError, generate_pattern, load_image
from .core.kernels import PRESETS, Kernel, KernelError, preset
from .core.reference import convolve, convolve_all, drop_bits
from .hardware import QuestaTestbench, TestbenchError, TestbenchResult
from .harness import Harness, HarnessRun

__all__ = [
    "PRESETS",
    "Harness",
    "HarnessRun",
    "ImageError",
    "Kernel",
    "KernelError",
    "LaneComparison",
    "QuestaTestbench",
    "RunComparison",
    "TestbenchError",
    "TestbenchResult",
    "Verdict",
    "convolve",
    "convolve_all",
    "drop_bits",
    "generate_pattern",
    "load_image",
    "preset",
]
