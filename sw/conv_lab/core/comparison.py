"""Hardware vs reference for one frame, computed once for every consumer.

The CLI report and the hardware regression need the same things from a run: a
verdict per kernel, frames on a display scale, PNG rows, and readable failure
lines. They live here so the two can never drift apart.

The rule this module exists to enforce: verdicts are computed from the RAW frames
when a comparison is built, and nothing afterwards can change them. `rectified()`
only changes what `frames()` returns for display, so ReLU - which collapses every
negative to zero - can never turn a real mismatch into a MATCH.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, replace

import numpy as np

from .kernels import Kernel
from .reference import apply_relu
from .rendering import normalise

GridRow = list[tuple[str, np.ndarray]]


@dataclass(frozen=True, slots=True)
class Verdict:
    """How closely one hardware frame matches its reference frame."""

    total: int
    mismatches: int
    max_abs_error: int
    first_mismatch: tuple[int, int] | None

    @classmethod
    def of(cls, hardware: np.ndarray, reference: np.ndarray) -> Verdict:
        diff = hardware.astype(np.int64) - reference.astype(np.int64)
        wrong = np.flatnonzero(diff.ravel())
        first = np.unravel_index(int(wrong[0]), diff.shape) if wrong.size else None
        return cls(
            total=int(diff.size),
            mismatches=int(wrong.size),
            max_abs_error=int(np.abs(diff).max()) if diff.size else 0,
            first_mismatch=(int(first[0]), int(first[1])) if first else None,
        )

    @property
    def exact(self) -> bool:
        return self.mismatches == 0

    def summary(self) -> str:
        if self.exact:
            return f"MATCH      all {self.total} feature(s) bit-exact against the golden model"
        row, col = self.first_mismatch or (-1, -1)
        return (
            f"MISMATCH   {self.mismatches}/{self.total} feature(s) differ, "
            f"max |error| {self.max_abs_error}, first at row {row} col {col}"
        )


@dataclass(frozen=True, slots=True, eq=False)
class LaneComparison:
    """One kernel's output: always from the reference, and from the hardware if simulated."""

    index: int
    kernel: Kernel
    reference: np.ndarray
    hardware: np.ndarray | None = None
    verdict: Verdict | None = None     # from the raw frames; None when not simulated
    relu: bool = False                 # display only - see frames()

    def frames(self) -> dict[str, np.ndarray]:
        """The frames to show or save, hardware first; rectified when `relu` is set."""
        if self.hardware is None:
            frames = {"reference": self.reference}
        else:
            frames = {"hardware": self.hardware, "reference": self.reference}
        if self.relu:
            return {name: apply_relu(frame) for name, frame in frames.items()}
        return frames

    def display_frames(self) -> dict[str, np.ndarray]:
        """frames() mapped to 0..255 on one grey scale, taken from the reference.

        The reference is the known-good frame, so it sets the range. A corrupted
        hardware frame therefore cannot repaint it: on a shared min/max, one huge
        wrong value (or a kernel landing in the wrong lane) stretches the scale and
        pushes the correct reference towards black. Hardware values outside the
        reference's range clip to black or white instead, which makes them easy to
        spot. Only a flat reference - every feature equal - borrows the combined
        range, so hardware that differs from it still shows.
        """
        frames = self.frames()
        lo, hi = int(frames["reference"].min()), int(frames["reference"].max())
        if lo == hi:
            lo = min(int(frame.min()) for frame in frames.values())
            hi = max(int(frame.max()) for frame in frames.values())
        return {name: normalise(frame, lo, hi) for name, frame in frames.items()}

    def failure(self) -> str | None:
        """One line describing a mismatch, quoting raw values; None when there is none."""
        if self.verdict is None or self.verdict.exact or self.hardware is None:
            return None
        row, col = self.verdict.first_mismatch or (0, 0)
        return (
            f"lane {self.index} ({self.kernel.name}): "
            f"{self.verdict.mismatches}/{self.verdict.total} differ; "
            f"first at row {row} col {col}: hardware {self.hardware[row, col]}, "
            f"reference {self.reference[row, col]}"
        )


@dataclass(frozen=True, slots=True, eq=False)
class RunComparison:
    """Every lane of one frame, with its verdicts fixed at construction."""

    image: np.ndarray
    lanes: tuple[LaneComparison, ...]

    @classmethod
    def build(cls, image: np.ndarray, kernels: Sequence[Kernel], reference: np.ndarray,
              hardware: np.ndarray | None = None) -> RunComparison:
        """`reference` and `hardware` are raw stacked frames, (len(kernels), N-K+1, N-K+1).

        Leave `hardware` out for a reference-only run: every lane then has no
        verdict, and nothing can fail.
        """
        lanes = tuple(
            LaneComparison(
                index=index,
                kernel=kernel,
                reference=reference[index],
                hardware=None if hardware is None else hardware[index],
                verdict=None if hardware is None else Verdict.of(hardware[index], reference[index]),
            )
            for index, kernel in enumerate(kernels)
        )
        return cls(image=image, lanes=lanes)

    @property
    def mismatched(self) -> list[LaneComparison]:
        return [lane for lane in self.lanes if lane.verdict is not None and not lane.verdict.exact]

    @property
    def all_match(self) -> bool:
        """No simulated lane disagrees - trivially true for a reference-only run."""
        return not self.mismatched

    def failures(self) -> list[str]:
        return [line for lane in self.mismatched if (line := lane.failure())]

    def rectified(self) -> RunComparison:
        """A copy whose frames() apply ReLU. Verdicts and failure() are untouched."""
        return replace(self, lanes=tuple(replace(lane, relu=True) for lane in self.lanes))

    def grid_rows(self, *, mismatched_only: bool = False) -> list[GridRow]:
        """Rows for rendering.save_grid, one per lane:
        `lane i: kernel | hardware: MATCH/MISMATCH | reference`, on display_frames' scale.
        """
        shown_input = normalise(self.image)
        rows: list[GridRow] = []
        for lane in self.mismatched if mismatched_only else self.lanes:
            row: GridRow = [(f"lane {lane.index}: {lane.kernel.name}", shown_input)]
            for name, frame in lane.display_frames().items():
                if name == "hardware" and lane.verdict is not None:
                    name = f"hardware: {'MATCH' if lane.verdict.exact else 'MISMATCH'}"
                row.append((name, frame))
            rows.append(row)
        return rows
