"""QuestaTestbench: conv_image_tb under QuestaSim, as a session.

    QuestaTestbench(run_dir).run(image, kernels)          -> TestbenchResult
    QuestaTestbench(run_dir).run_stream(frames, kernels)  -> [TestbenchResult, ...]

`image` is an (N, N) uint8 array, `kernels` a sequence of Kernel. Each run
elaborates conv_system for that exact geometry and returns every feature the
hardware emitted, as int32 of shape (len(kernels), N-K+1, N-K+1) per frame.
run_stream sends several frames through one simulation after a single reset,
with no reset between them, the way conv_system streams video.
The files a run exchanges are defined in contract.py, the commands in questa.py.
"""

from __future__ import annotations

import time
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Final

import numpy as np

from ..core.images import validate_dimensions
from ..core.kernels import Kernel, common_size
from . import questa
from .contract import TestbenchError, parse_stream_results, write_stream_stimulus

DEFAULT_RUN_DIR: Final = questa.REPO_ROOT / "sw" / ".run"


@dataclass(frozen=True, slots=True)
class TestbenchResult:
    __test__ = False      # the name starts with "Test"; stop pytest collecting it

    features: np.ndarray  # (num_kernels, out_size, out_size), int32
    drop_bits: int        # DROP as the testbench reported it
    elapsed_s: float      # the whole simulation, shared by every frame of a stream
    run_dir: Path
    log: str

    @property
    def output_size(self) -> int:
        return int(self.features.shape[1])


class QuestaTestbench:
    """conv_image_tb under QuestaSim, as a session that owns its run directory.

    The first successful run compiles the RTL into run_dir; later runs reuse
    that library and only re-elaborate, because only elaboration depends on
    INPUT_SIZE, WINDOW_SIZE and NUM_KERNELS. A failed run leaves the next one to
    compile again. Runs share run_dir's files, so use one instance at a time.
    """

    def __init__(self, run_dir: Path | None = None, *, echo: bool = False) -> None:
        self.run_dir = Path(run_dir or DEFAULT_RUN_DIR)
        self.echo = echo
        self._compiled = False

    def run(self, image: np.ndarray, kernels: Sequence[Kernel]) -> TestbenchResult:
        """Convolve `image` with every kernel in `kernels` on the SystemVerilog testbench."""
        return self.run_stream([image], kernels)[0]

    def run_stream(self, frames: Sequence[np.ndarray], kernels: Sequence[Kernel], *,
                   gap: int = 0) -> list[TestbenchResult]:
        """Stream `frames` through one simulation, one reset, no reset between frames.

        gap=0 sends them back to back (the next frame's first pixel on the cycle
        after the previous frame's last one); gap>0 leaves that many idle cycles.
        Returns one result per frame, in order.
        """
        if not frames:
            raise TestbenchError("a stream needs at least one frame")
        if gap < 0:
            raise TestbenchError(f"gap must be zero or positive, got {gap}")
        window = self._validate(frames[0], kernels)
        if any(frame.shape != frames[0].shape for frame in frames):
            raise TestbenchError("every frame of a stream must have the same size")

        input_size = int(frames[0].shape[0])
        output_size = input_size - window + 1
        self.run_dir.mkdir(parents=True, exist_ok=True)

        result_path = self.run_dir / "features.txt"
        result_path.unlink(missing_ok=True)
        write_stream_stimulus(self.run_dir / "stimulus.txt", frames, kernels)

        steps = questa.commands(self.run_dir, input_size, window, len(kernels),
                                recompile=not self._compiled, gap=gap)
        started = time.monotonic()
        log = questa.execute(steps, cwd=self.run_dir, echo=self.echo)
        elapsed = time.monotonic() - started
        (self.run_dir / "sim.log").write_text(log, encoding="utf-8", errors="replace")

        if "STATUS: OK" not in log:
            raise TestbenchError(
                f"the Questa run did not complete - see {self.run_dir / 'sim.log'}\n\n"
                + _tail(log)
            )
        self._compiled = True

        features, drop = parse_stream_results(result_path, len(kernels), output_size, len(frames))
        return [TestbenchResult(features=frame, drop_bits=drop, elapsed_s=elapsed,
                                run_dir=self.run_dir, log=log)
                for frame in features]

    @staticmethod
    def _validate(image: np.ndarray, kernels: Sequence[Kernel]) -> int:
        """Reject what conv_system cannot be elaborated for; return the window size."""
        window = common_size(kernels)
        validate_dimensions(*image.shape, window)
        if not questa.MANIFEST.is_file():
            raise TestbenchError(f"missing compile manifest {questa.MANIFEST}")
        return window


def _tail(log: str, lines: int = 15) -> str:
    return "\n".join(log.splitlines()[-lines:])
