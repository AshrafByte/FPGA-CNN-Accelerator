"""core.comparison: verdicts, the ReLU rule, the display scale, and the rows both front ends render."""

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
    # ...even though the rectified frames themselves are now indistinguishable.
    frames = shown.lanes[0].frames()
    assert np.array_equal(frames["hardware"], frames["reference"])


def test_a_reference_only_comparison_has_nothing_to_fail():
    image = generate_pattern("ramp", 12)
    kernels = [preset("sobel_x")]
    comparison = RunComparison.build(image, kernels, reference.convolve_all(image, kernels))
    lane = comparison.lanes[0]

    assert lane.verdict is None and lane.hardware is None
    assert comparison.all_match and comparison.failures() == []
    assert list(lane.frames()) == ["reference"]
    assert [label for label, _ in comparison.grid_rows()[0]] == ["lane 0: sobel_x", "reference"]


def test_grid_rows_label_each_lane_with_its_verdict():
    image = generate_pattern("noise", 10, seed=2)
    kernels = [preset("sobel_x"), preset("gaussian_blur")]
    model = reference.convolve_all(image, kernels)
    hardware = model.copy()
    hardware[1, 0, 0] += 3
    comparison = RunComparison.build(image, kernels, model, hardware)

    rows = comparison.grid_rows()
    assert [label for label, _ in rows[0]] == ["lane 0: sobel_x", "hardware: MATCH", "reference"]
    assert [label for label, _ in rows[1]] == ["lane 1: gaussian_blur", "hardware: MISMATCH", "reference"]
    assert [row[0][0] for row in comparison.grid_rows(mismatched_only=True)] == ["lane 1: gaussian_blur"]


def test_corrupted_hardware_cannot_repaint_the_reference():
    """One wildly wrong hardware value used to stretch a shared min/max and push the
    correct reference towards black. The reference now sets the scale, so it looks
    the same however broken the hardware is, and the bad value clips to white."""
    image = generate_pattern("noise", 12, seed=5)
    kernel = preset("sobel_x")
    golden = reference.convolve(image, kernel)[np.newaxis]
    corrupt = golden.copy()
    corrupt[0, 0, 0] = 30000

    clean = RunComparison.build(image, [kernel], golden, golden).lanes[0].display_frames()
    broken = RunComparison.build(image, [kernel], golden, corrupt).lanes[0].display_frames()

    assert np.array_equal(broken["reference"], clean["reference"])
    assert broken["hardware"][0, 0] == 255
    assert np.array_equal(broken["hardware"][1:], clean["hardware"][1:])


def test_a_flat_reference_still_shows_hardware_that_differs():
    image = np.zeros((6, 6), dtype=np.uint8)
    kernel = preset("sobel_x")
    golden = reference.convolve(image, kernel)[np.newaxis]     # every feature 0
    corrupt = golden.copy()
    corrupt[0, 1, 1] = 7

    shown = RunComparison.build(image, [kernel], golden, corrupt).lanes[0].display_frames()
    assert shown["hardware"][1, 1] != shown["hardware"][0, 0]
    assert shown["hardware"][0, 0] == shown["reference"][0, 0]
