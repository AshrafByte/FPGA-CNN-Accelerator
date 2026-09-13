"""core.comparison: verdicts, the ReLU rule, and the rows both front ends render."""

from __future__ import annotations

import numpy as np

from conv_lab.core import reference
from conv_lab.core.comparison import RunComparison, Verdict
from conv_lab.core.images import generate_pattern
from conv_lab.core.kernels import preset


def test_verdict_counts_and_locates_mismatches():
    reference_frame = np.zeros((3, 3), dtype=np.int32)
    hardware_frame = reference_frame.copy()
    hardware_frame[1, 2] = -5
    hardware_frame[2, 0] = 2

    verdict = Verdict.of(hardware_frame, reference_frame)
    assert (verdict.total, verdict.mismatches, verdict.max_abs_error) == (9, 2, 5)
    assert verdict.first_mismatch == (1, 2)
    assert not verdict.exact and "MISMATCH" in verdict.summary()
    assert Verdict.of(reference_frame, reference_frame).exact


def test_rectifying_a_comparison_never_changes_its_verdict():
    """The ReLU rule, enforced by structure: rectified() changes frames() and nothing else."""
    image = generate_pattern("circle", 20)
    kernel = preset("sobel_x")
    golden = reference.convolve(image, kernel)
    corrupt = golden.copy()
    row, col = np.argwhere(golden < 0)[0]
    corrupt[row, col] -= 1                          # a real mismatch that ReLU would hide

    raw = RunComparison.build(image, [kernel], golden[np.newaxis], corrupt[np.newaxis])
    shown = raw.rectified()

    assert not raw.all_match and not shown.all_match
    assert shown.lanes[0].verdict == raw.lanes[0].verdict
    assert shown.failures() == raw.failures()
    assert np.array_equal(shown.lanes[0].difference(), raw.lanes[0].difference())
    # ...even though the rectified frames themselves are now indistinguishable.
    frames = shown.lanes[0].frames()
    assert np.array_equal(frames["hardware"], frames["reference"])


def test_a_reference_only_comparison_has_nothing_to_fail():
    image = generate_pattern("ramp", 12)
    kernels = [preset("sobel_x")]
    comparison = RunComparison.build(image, kernels, reference.convolve_all(image, kernels))
    lane = comparison.lanes[0]

    assert lane.verdict is None and lane.hardware is None and lane.difference() is None
    assert comparison.all_match and comparison.failures() == []
    assert list(lane.frames()) == ["reference"]
    assert [label for label, _ in comparison.grid_rows(difference=True)[0]] == \
        ["lane 0: sobel_x", "reference"]


def test_grid_rows_label_verdicts_and_black_out_matching_differences():
    image = generate_pattern("noise", 10, seed=2)
    kernels = [preset("sobel_x"), preset("gaussian_blur")]
    model = reference.convolve_all(image, kernels)
    hardware = model.copy()
    hardware[1, 0, 0] += 3
    comparison = RunComparison.build(image, kernels, model, hardware)

    rows = comparison.grid_rows(difference=True)
    assert [label for label, _ in rows[0]] == \
        ["lane 0: sobel_x", "hardware: MATCH", "reference", "|difference|"]
    assert rows[1][1][0] == "hardware: MISMATCH"
    assert rows[0][3][1].max() == 0                 # matching lane: solid black
    assert rows[1][3][1].max() == 255               # the one bad feature lights up
    assert len(comparison.grid_rows(mismatched_only=True)) == 1
    assert len(comparison.grid_rows()[0]) == 3      # no difference column unless asked
