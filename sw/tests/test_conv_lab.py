"""Checks for everything that does not need a simulator.

The interesting one is test_pack_kernel_matches_hardware_tap_order: it replays
window_generator's column-descending indexing in Python and confirms that the
flip in pack_kernel is what turns it back into an ordinary correlation. Get that
wrong and every result is silently mirrored, which no amount of staring at a
blurred image would reveal.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from conv_lab import reference
from conv_lab.imaging import ImageError, generate_pattern, normalise, to_ascii, validate_dimensions
from conv_lab.kernels import PRESETS, Kernel, KernelError, preset
from conv_lab.cli import build_parser, run_reference
from conv_lab.cli import main as cli_main
from conv_lab.testbench import (
    MANIFEST,
    TOP,
    pack_kernel,
    parse_results,
    questa_steps,
    write_stimulus,
)


# --------------------------------------------------------------------------- #
# Kernels
# --------------------------------------------------------------------------- #

def test_every_preset_is_loadable_by_the_hardware():
    for name, kernel in PRESETS.items():
        assert kernel.name == name
        assert kernel.size % 2 == 1
        assert all(-128 <= w <= 127 for w in kernel.flat())


def test_unity_gain_presets_really_are_unity():
    drop = reference.drop_bits(3)
    for name in ("identity", "gaussian_blur", "sharpen", "emboss"):
        assert PRESETS[name].hardware_gain(drop) == 1.0


@pytest.mark.parametrize(
    "text",
    [
        "1 0 -1; 2 0 -2; 1 0 -1",
        "1,0,-1\n2,0,-2\n1,0,-1",
        "[[1, 0, -1], [2, 0, -2], [1, 0, -1]]",
    ],
)
def test_parse_accepts_the_usual_ways_of_typing_a_matrix(text):
    assert Kernel.parse(text).rows == PRESETS["sobel_x"].rows


@pytest.mark.parametrize(
    ("text", "message"),
    [
        ("1 2; 3 4", "odd-sized"),
        ("1 2 3; 4 5", "square"),
        ("1 2 3; 4 x 6; 7 8 9", "not an integer"),
        ("", "no kernel weights"),
        ("200 0 0; 0 0 0; 0 0 0", "signed 8-bit"),
    ],
)
def test_malformed_kernels_are_rejected_with_a_useful_message(text, message):
    with pytest.raises(KernelError, match=message):
        Kernel.parse(text)


def test_unknown_preset_lists_the_alternatives():
    with pytest.raises(KernelError, match="sobel_x"):
        preset("sobel_diagonal")


# --------------------------------------------------------------------------- #
# Reference model
# --------------------------------------------------------------------------- #

def test_identity_kernel_reproduces_the_interior_of_the_frame():
    image = generate_pattern("noise", 12, seed=7)
    out = reference.convolve(image, preset("identity"))
    assert np.array_equal(out, image[1:-1, 1:-1])


def test_round_half_to_even_not_half_away_from_zero():
    # box_blur sums a 3x3 window; a uniform frame of v gives a MAC of 9v, and
    # 9v/16 lands exactly on .5 for v chosen so 9v % 16 == 8.
    for value, expected in ((16, 9), (48, 27)):  # 144/16=9 exact, 432/16=27 exact
        frame = np.full((5, 5), value, dtype=np.uint8)
        assert reference.convolve(frame, preset("box_blur"))[0, 0] == expected

    # 9*80 = 720, 720/16 = 45 exact; 9*81 = 729 -> 45.5625 -> 46 (above the half)
    assert reference.convolve(np.full((5, 5), 81, np.uint8), preset("box_blur"))[0, 0] == 46
    # 9*112 = 1008 -> 63.0 exact
    assert reference.convolve(np.full((5, 5), 112, np.uint8), preset("box_blur"))[0, 0] == 63


def test_ties_round_toward_the_even_quotient():
    # A single tap of 1 with drop=4: MAC == pixel, so the tie cases are pixels
    # ending in 8 -> quotient .5 -> must land on the even neighbour.
    tap = Kernel("single", ((0, 0, 0), (0, 1, 0), (0, 0, 0)))
    for pixel, expected in ((8, 0), (24, 2), (40, 2), (56, 4)):
        frame = np.full((5, 5), pixel, dtype=np.uint8)
        assert reference.convolve(frame, tap)[0, 0] == expected, pixel


def test_the_16_bit_clamp_is_unreachable_for_an_8_bit_pixel_path():
    # DROP == $clog2(K**2), so the worst case is 255 * 128 * K**2 >> $clog2(K**2),
    # which never exceeds 255 * 128 = 32640 < 32767. Confirm the extremes of the
    # legal weight range stay inside the feature width for every supported K.
    limit = (1 << 15) - 1
    for size in (3, 5, 7):
        white = np.full((size + 2, size + 2), 255, dtype=np.uint8)
        for weight in (127, -128):
            hot = Kernel("hot", tuple((weight,) * size for _ in range(size)))
            out = reference.convolve(white, hot)
            assert -limit - 1 < out.min() <= out.max() < limit, (size, weight)


def test_negative_weights_give_negative_features():
    image = generate_pattern("bars", 16)
    out = reference.convolve(image, preset("sobel_x"))
    assert out.min() < 0 < out.max()


def test_output_geometry_is_valid_only():
    image = generate_pattern("ramp", 20)
    assert reference.convolve(image, preset("sobel_x")).shape == (18, 18)


def test_accumulator_width_matches_the_rtl():
    assert reference.accumulator_width(3) == 20  # 2*8 + $clog2(9)
    assert reference.drop_bits(3) == 4


# --------------------------------------------------------------------------- #
# Hardware interface
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
# Simulator command construction
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
    monkeypatch.setattr("conv_lab.testbench.shutil.which", lambda _: "/opt/questa/bin/vsim")
    steps = questa_steps(tmp_path, input_size=64, window=3, num_kernels=2)
    vlib, vlog, vsim = steps

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
    monkeypatch.setattr("conv_lab.testbench.shutil.which", lambda _: "vsim")
    (tmp_path / "work").mkdir()

    steps = questa_steps(tmp_path, input_size=16, window=3, num_kernels=1)
    assert not any(step.startswith("vlib") for step in steps)
    assert len(steps) == 2 and steps[0].startswith("vlog") and steps[1].startswith("vsim")



def test_with_no_questa_the_error_points_at_reference_mode(monkeypatch, tmp_path):
    monkeypatch.setattr("conv_lab.testbench.shutil.which", lambda _: None)
    with pytest.raises(Exception, match="--reference"):
        questa_steps(tmp_path, 32, 3, 1)


# --------------------------------------------------------------------------- #
# Reference-only compute path
# --------------------------------------------------------------------------- #

def test_reference_mode_returns_one_frame_per_kernel_without_a_simulator(monkeypatch):
    # Any attempt to reach a simulator from this path is a bug.
    monkeypatch.setattr("conv_lab.cli.run", _explode)

    image = generate_pattern("circle", 20)
    kernels = [preset("sobel_x"), preset("gaussian_blur")]
    features, drop, footer = run_reference(image, kernels)

    assert features.shape == (2, 18, 18)
    assert drop == reference.drop_bits(3)
    for index, kernel in enumerate(kernels):
        assert np.array_equal(features[index], reference.convolve(image, kernel))
    assert "no simulator" in footer


def _explode(*args, **kwargs):
    raise AssertionError("reference mode must not invoke the testbench")


def test_the_simulator_flag_is_gone_now_that_questa_is_the_only_backend():
    with pytest.raises(SystemExit):
        build_parser().parse_args(["--simulator", "questa"])


def test_reference_mode_reports_no_verdict(capsys, monkeypatch, tmp_path):
    monkeypatch.setattr("conv_lab.cli.run", _explode)
    exit_code = cli_main(["--pattern", "ramp", "--size", "12",
                          "--kernel", "sobel_x", "--reference"])
    out = capsys.readouterr().out

    assert exit_code == 0
    assert "MATCH" not in out and "MISMATCH" not in out
    assert "  hardware   " not in out      # the stats row, not the gain line
    assert "  model      " in out
    assert "reference model" in out


# --------------------------------------------------------------------------- #
# Geometry and display
# --------------------------------------------------------------------------- #

@pytest.mark.parametrize(
    ("height", "width", "message"),
    [
        (32, 64, "square"),
        (3, 3, "too small"),
        (4096, 4096, "exceeds"),
    ],
)
def test_bad_geometry_is_rejected(height, width, message):
    with pytest.raises(ImageError, match=message):
        validate_dimensions(height, width, 3)


def test_smallest_legal_frame_is_accepted():
    validate_dimensions(4, 4, 3)


def test_patterns_are_single_channel_uint8():
    for name in ("ramp", "checker", "circle", "bars", "noise"):
        frame = generate_pattern(name, 16)
        assert frame.shape == (16, 16)
        assert frame.dtype == np.uint8


def test_normalise_stretches_signed_features_into_display_range():
    features = np.array([[-1000, 0], [500, 1000]], dtype=np.int32)
    shown = normalise(features)
    assert (shown.min(), shown.max()) == (0, 255)

    flat = normalise(np.zeros((4, 4), dtype=np.int32))
    assert np.all(flat == 128)


def test_ascii_preview_is_rectangular():
    rows = to_ascii(generate_pattern("circle", 32), width=16)
    assert len({len(row) for row in rows}) == 1
