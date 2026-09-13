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
from conv_lab.hardware.contract import pack_kernel, parse_results, write_stimulus
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


@pytest.mark.parametrize(
    ("body", "message"),
    [
        ("2 2 4\n0 0\n1 1\n", "expected 4 feature row"),
        ("3 2 4\n0 0\n", "result header says"),
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
