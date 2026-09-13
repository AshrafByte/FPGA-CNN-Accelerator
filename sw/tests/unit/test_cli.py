"""cli: flags, the printed report, and the exit codes a front end owes its caller."""

from __future__ import annotations

import numpy as np
import pytest
from PIL import Image

from conv_lab.cli import main
from conv_lab.cli.app import build_parser
from conv_lab.cli.report import report
from conv_lab.core import reference
from conv_lab.core.comparison import RunComparison
from conv_lab.core.images import generate_pattern
from conv_lab.core.kernels import preset
from conv_lab.core.rendering import save_grid
from conv_lab.hardware import TestbenchResult
from conv_lab.harness import HarnessRun

TESTBENCH = "conv_lab.cli.app.QuestaTestbench"


def _explode(*args, **kwargs):
    raise AssertionError("reference mode must not invoke the testbench")


def test_the_simulator_flag_is_gone_now_that_questa_is_the_only_backend():
    with pytest.raises(SystemExit):
        build_parser().parse_args(["--simulator", "questa"])


def test_relu_does_not_weaken_the_hardware_check(capsys, tmp_path):
    """The verdict must be computed BEFORE rectification.

    ReLU collapses every negative to zero, so comparing rectified frames would
    call a hardware value of -5 equal to a model value of -9 and report MATCH on
    a broken DUT. This plants exactly that disagreement - two frames that differ
    only where both are negative - and asserts the mismatch is still caught.
    """
    image = generate_pattern("circle", 20)
    kernel = preset("sobel_x")
    golden = reference.convolve(image, kernel)

    corrupt = golden.copy()
    negatives = np.argwhere(golden < 0)
    assert negatives.size, "need negative features for this test to mean anything"
    row, col = negatives[0]
    corrupt[row, col] = golden[row, col] - 1        # still negative, so ReLU hides it

    args = build_parser().parse_args(["--pattern", "circle", "--size", "20",
                                      "--kernel", "sobel_x", "--relu"])
    hardware = TestbenchResult(features=corrupt[np.newaxis], drop_bits=4,
                               elapsed_s=0.0, run_dir=tmp_path, log="")
    comparison = RunComparison.build(image, [kernel], golden[np.newaxis], hardware.features)
    matched = report(HarnessRun(comparison, hardware), args)
    out = capsys.readouterr().out

    assert matched is False
    assert "MISMATCH" in out
    assert "relu" in out               # rectified frame still reported alongside


def test_reference_mode_reports_no_verdict(capsys, monkeypatch):
    monkeypatch.setattr(TESTBENCH, _explode)
    exit_code = main(["--pattern", "ramp", "--size", "12", "--kernel", "sobel_x", "--reference"])
    out = capsys.readouterr().out

    assert exit_code == 0
    assert "MATCH" not in out and "MISMATCH" not in out
    assert "  hardware   " not in out      # the stats row, not the gain line
    assert "  reference  " in out
    assert "reference model" in out


def test_one_run_computes_hardware_and_reference_and_shows_both(capsys, monkeypatch, tmp_path):
    """The default run yields both frames from a single invocation. The testbench is
    stubbed with the reference's own frames, so this checks reporting, not the RTL."""
    calls = []

    class FakeTestbench:
        def __init__(self, *args, **kwargs):
            pass

        def run(self, image, kernels):
            calls.append(len(kernels))
            return TestbenchResult(features=reference.convolve_all(image, kernels), drop_bits=4,
                                   elapsed_s=0.0, run_dir=tmp_path, log="STATUS: OK")

    monkeypatch.setattr(TESTBENCH, FakeTestbench)
    png = tmp_path / "compare.png"
    exit_code = main(["--pattern", "circle", "--size", "16", "--kernel", "sobel_x",
                      "--kernel", "gaussian_blur", "--png", str(png)])
    out = capsys.readouterr().out

    assert exit_code == 0
    assert calls == [2]                        # one simulation carries both kernels
    assert out.count("  hardware   ") == 2 and out.count("  reference  ") == 2
    assert "hardware (14x14)" in out and "reference (14x14)" in out
    assert "MATCH: hardware and reference agree" in out

    one_row = save_grid([[("input", np.zeros((16, 16), np.uint8))] * 3], tmp_path / "row.png")
    with Image.open(png) as grid, Image.open(one_row) as row:
        assert grid.width == row.width         # input | hardware | reference
        assert grid.height > row.height        # one row per kernel


def test_a_hardware_mismatch_fails_the_run(capsys, monkeypatch, tmp_path):
    class BrokenTestbench:
        def __init__(self, *args, **kwargs):
            pass

        def run(self, image, kernels):
            features = reference.convolve_all(image, kernels)
            features[0, 3, 3] += 1
            return TestbenchResult(features=features, drop_bits=4, elapsed_s=0.0,
                                   run_dir=tmp_path, log="STATUS: OK")

    monkeypatch.setattr(TESTBENCH, BrokenTestbench)
    exit_code = main(["--pattern", "noise", "--size", "12", "--kernel", "sobel_x"])
    out = capsys.readouterr().out

    assert exit_code == 1
    assert "MISMATCH in 1 of 1 kernel(s): sobel_x" in out


def test_mixed_kernel_sizes_are_reported_instead_of_crashing(capsys):
    exit_code = main(["--pattern", "ramp", "--size", "16", "--kernel", "sobel_x",
                      "--weights", "1 1 1 1 1; 1 1 1 1 1; 1 1 1 1 1; 1 1 1 1 1; 1 1 1 1 1",
                      "--reference"])
    assert exit_code == 2
    assert "must be the same size" in capsys.readouterr().err
