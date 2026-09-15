"""hardware: the run-directory contract, the Questa commands, and the testbench session.

The most important check here is test_pack_kernel_matches_hardware_tap_order: it
replays window_generator's column-descending indexing in Python and confirms that
the flip in pack_kernel is what turns it back into an ordinary correlation. Get
that wrong and every result is silently mirrored, which no amount of staring at a
blurred image would reveal.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from conv_lab.core import reference
from conv_lab.core.images import generate_pattern
from conv_lab.core.kernels import PRESETS, preset
from conv_lab.hardware import QuestaTestbench
from conv_lab.hardware.contract import (
    pack_kernel,
    parse_results,
    parse_stream_results,
    write_stimulus,
    write_stream_stimulus,
)
from conv_lab.hardware.questa import MANIFEST, TOP, commands

WHICH = "conv_lab.hardware.questa.shutil.which"


# --------------------------------------------------------------------------- #
# The run-directory contract
# --------------------------------------------------------------------------- #

def _hardware_mac(image: np.ndarray, packed: list[int], size: int) -> np.ndarray:
    """Replay the DUT exactly: window[kr*K + kc] == image[r+kr][c+(K-1-kc)]."""
    n = image.shape[0]
    out = np.zeros((n - size + 1, n - size + 1), dtype=np.int64)
    for r in range(out.shape[0]):
        for c in range(out.shape[1]):
            out[r, c] = sum(
                int(image[r + kr, c + (size - 1 - kc)]) * packed[kr * size + kc]
                for kr in range(size)
                for kc in range(size)
            )
    return out


def test_pack_kernel_matches_hardware_tap_order():
    image = generate_pattern("noise", 9, seed=3)
    for kernel in PRESETS.values():
        weights = np.array(kernel.rows, dtype=np.int64)
        expected = reference._valid_correlate(image, weights)
        assert np.array_equal(_hardware_mac(image, pack_kernel(kernel), kernel.size), expected), \
            kernel.name


def test_an_asymmetric_kernel_would_catch_a_missing_flip():
    # Guard against pack_kernel quietly becoming the identity: sobel_x is not
    # equal to its own row-reversal, so the two orders must differ.
    sobel = preset("sobel_x")
    assert pack_kernel(sobel) != sobel.flat()


def test_stimulus_file_layout(tmp_path):
    image = np.arange(16, dtype=np.uint8).reshape(4, 4)
    path = tmp_path / "stimulus.txt"
    write_stimulus(path, image, [preset("sobel_x"), preset("sobel_y")])

    values = path.read_text().split()
    assert values[:3] == ["4", "3", "2"]
    taps = 9
    assert [int(v) for v in values[3 : 3 + taps]] == pack_kernel(preset("sobel_x"))
    assert [int(v) for v in values[3 + taps : 3 + 2 * taps]] == pack_kernel(preset("sobel_y"))
    assert [int(v) for v in values[3 + 2 * taps :]] == list(range(16))


def test_result_file_round_trips_into_kernel_major_frames(tmp_path):
    path = tmp_path / "features.txt"
    # 2x2 output, 2 kernels: kernel 0 counts up, kernel 1 counts down.
    path.write_text("# header\n2 2 4\n0 -0\n1 -1\n2 -2\n3 -3\n")

    features, drop = parse_results(path, num_kernels=2, output_size=2)
    assert drop == 4
    assert np.array_equal(features[0], [[0, 1], [2, 3]])
    assert np.array_equal(features[1], [[0, -1], [-2, -3]])


def test_stream_stimulus_holds_every_frame_after_the_kernels(tmp_path):
    first = np.arange(16, dtype=np.uint8).reshape(4, 4)
    second = first[::-1].copy()
    path = tmp_path / "stimulus.txt"
    write_stream_stimulus(path, [first, second], [preset("identity")])

    values = [int(v) for v in path.read_text().split()]
    assert values[:3] == [4, 3, 1]
    assert values[3:12] == pack_kernel(preset("identity"))
    assert values[12:28] == first.reshape(-1).tolist()
    assert values[28:] == second.reshape(-1).tolist()


def test_a_stream_rejects_frames_of_different_sizes(tmp_path):
    with pytest.raises(ValueError, match="same|must be"):
        write_stream_stimulus(tmp_path / "s.txt", [np.zeros((4, 4), np.uint8), np.zeros((5, 5), np.uint8)],
                              [preset("identity")])


def test_stream_result_file_splits_into_frames(tmp_path):
    path = tmp_path / "features.txt"
    # 2x2 output, 2 kernels, 2 frames: kernel 0 counts up, kernel 1 counts down.
    lines = ["# header", "2 2 4 2"] + [f"{n} {-n}" for n in range(8)]
    path.write_text("\n".join(lines) + "\n")

    frames, drop = parse_stream_results(path, num_kernels=2, output_size=2, num_frames=2)
    assert drop == 4 and frames.shape == (2, 2, 2, 2)
    assert np.array_equal(frames[0][0], [[0, 1], [2, 3]])
    assert np.array_equal(frames[1][0], [[4, 5], [6, 7]])
    assert np.array_equal(frames[1][1], [[-4, -5], [-6, -7]])


def test_result_header_frame_count_must_match(tmp_path):
    path = tmp_path / "features.txt"
    path.write_text("2 1 4 3\n" + "0\n" * 12)
    with pytest.raises(Exception, match="result header says"):
        parse_stream_results(path, num_kernels=1, output_size=2, num_frames=2)


@pytest.mark.parametrize(
    ("body", "message"),
    [
        ("2 2 4\n0 0\n1 1\n", "expected 4 feature row"),
        ("3 2 4\n0 0\n", "result header says"),
        ("2 2 4 2\n0 0\n1 1\n2 2\n3 3\n", "result header says"),
        ("", "is empty"),
    ],
)
def test_corrupt_result_files_are_reported(tmp_path, body, message):
    path = tmp_path / "features.txt"
    path.write_text(body)
    with pytest.raises(Exception, match=message):
        parse_results(path, num_kernels=2, output_size=2)


# --------------------------------------------------------------------------- #
# Questa commands
# --------------------------------------------------------------------------- #

def test_the_compile_manifest_pulls_in_the_image_testbench():
    """The manifest is the repo's, not conv_lab's - a filelist reshuffle that drops
    conv_image_tb would otherwise only show up as 'module not found' at elaboration."""
    assert MANIFEST.is_file(), MANIFEST
    reachable = _manifest_sources(MANIFEST)
    assert any(p.name == f"{TOP}.sv" for p in reachable), \
        f"{TOP}.sv is not reachable from {MANIFEST}"


def _manifest_sources(manifest: Path) -> list[Path]:
    """Expand a filelist the way Questa's -F does: paths relative to the file."""
    found: list[Path] = []
    for raw in manifest.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith(("+", "#")):
            continue
        if line.startswith("-F ") or line.startswith("-f "):
            found += _manifest_sources((manifest.parent / line[3:].strip()).resolve())
        else:
            found.append((manifest.parent / line).resolve())
    return found


def test_questa_command_carries_every_geometry_override(monkeypatch, tmp_path):
    monkeypatch.setattr(WHICH, lambda _: "/opt/questa/bin/vsim")
    vlib, vlog, vsim = commands(tmp_path, input_size=64, window=3, num_kernels=2)

    assert vlib == "vlib work"
    assert "-sv" in vlog and str(MANIFEST) in vlog
    for override in ("-gINPUT_SIZE=64", "-gWINDOW_SIZE=3", "-gNUM_KERNELS=2"):
        assert override in vsim, override
    assert f"work.{TOP}" in vsim
    assert "+stim=stimulus.txt" in vsim and "+result=features.txt" in vsim
    assert "run -all" in vsim and "quit -f" in vsim
    assert "+gap" not in vsim


def test_questa_command_passes_the_frame_gap(monkeypatch, tmp_path):
    monkeypatch.setattr(WHICH, lambda _: "vsim")
    *_, vsim = commands(tmp_path, input_size=16, window=3, num_kernels=1, gap=7)
    assert "+gap=7" in vsim


def test_questa_skips_vlib_when_the_library_already_exists(monkeypatch, tmp_path):
    """Second and later runs must not re-create the library. cmd.exe binds && inside
    an if, so this decision is made in Python rather than in shell syntax - and a
    regression here would silently execute nothing at all on Windows."""
    monkeypatch.setattr(WHICH, lambda _: "vsim")
    (tmp_path / "work").mkdir()

    steps = commands(tmp_path, input_size=16, window=3, num_kernels=1)
    assert not any(step.startswith("vlib") for step in steps)
    assert len(steps) == 2 and steps[0].startswith("vlog") and steps[1].startswith("vsim")


def test_questa_commands_can_reuse_a_compiled_library(monkeypatch, tmp_path):
    monkeypatch.setattr(WHICH, lambda _: "vsim")
    (tmp_path / "work").mkdir()
    steps = commands(tmp_path, input_size=16, window=3, num_kernels=1, recompile=False)
    assert len(steps) == 1 and steps[0].startswith("vsim")


def test_with_no_questa_the_error_points_at_reference_mode(monkeypatch, tmp_path):
    monkeypatch.setattr(WHICH, lambda _: None)
    with pytest.raises(Exception, match="--reference"):
        commands(tmp_path, 32, 3, 1)


# --------------------------------------------------------------------------- #
# The testbench session
# --------------------------------------------------------------------------- #

def test_the_testbench_compiles_on_its_first_run_only(monkeypatch, tmp_path):
    monkeypatch.setattr(WHICH, lambda _: "vsim")
    image = generate_pattern("ramp", 8)
    seen = []

    def fake_execute(steps, *, cwd, echo):
        seen.append([step.split()[0] for step in steps])
        (cwd / "work").mkdir(exist_ok=True)
        lines = ["# fake", "6 1 4"] + ["0"] * 36
        (cwd / "features.txt").write_text("\n".join(lines) + "\n")
        return "STATUS: OK"

    monkeypatch.setattr("conv_lab.hardware.questa.execute", fake_execute)
    bench = QuestaTestbench(tmp_path)
    bench.run(image, [preset("identity")])
    bench.run(image, [preset("identity")])

    assert seen == [["vlib", "vlog", "vsim"], ["vsim"]]


def test_a_stream_is_one_simulation_with_one_result_per_frame(monkeypatch, tmp_path):
    monkeypatch.setattr(WHICH, lambda _: "vsim")
    frames = [generate_pattern("ramp", 8), generate_pattern("checker", 8)]
    runs = []

    def fake_execute(steps, *, cwd, echo):
        runs.append(steps)
        stimulus = (cwd / "stimulus.txt").read_text().split()
        assert len(stimulus) == 3 + 9 + 2 * 64            # header, kernel, two frames
        lines = ["# fake", "6 1 4 2"] + [str(n % 36) for n in range(72)]
        (cwd / "features.txt").write_text("\n".join(lines) + "\n")
        return "STATUS: OK"

    monkeypatch.setattr("conv_lab.hardware.questa.execute", fake_execute)
    results = QuestaTestbench(tmp_path).run_stream(frames, [preset("identity")], gap=3)

    assert len(runs) == 1 and "+gap=3" in runs[0][-1]
    assert len(results) == 2
    assert results[0].features.shape == (1, 6, 6)
    assert np.array_equal(results[0].features, results[1].features)
