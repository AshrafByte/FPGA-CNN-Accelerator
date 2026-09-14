"""Hardware regression: conv_image_tb under QuestaSim against the reference model.

Every case is a real simulation, so the suite is built to spend them well:

  * Kernels ride as parallel lanes. conv_system evaluates NUM_KERNELS kernels in
    the same frame, so twelve presets cost one simulation rather than twelve,
    and every lane doubles as an isolation check on its neighbours.
  * One Harness with one QuestaTestbench serves the whole session, so the RTL
    compiles once and each case only re-elaborates for its own geometry.
  * On failure the stimulus, the hardware's features, the simulator log and a
    hardware | reference PNG are kept in the test's tmp directory, and the
    message names each failing lane with its first differing feature.

A frame runs through exactly the pipeline the CLI uses (conv_lab.harness), so a
change to what a run does reaches this suite without touching it.

Skipped automatically when vsim is not on PATH.

    pytest -m hardware                                   # the regression at 32x32
    pytest -m hardware --sizes 16,32,64                  # size-independent cases at each size
    pytest -m hardware --seeds 200                       # more randomised cases
    pytest -m hardware --relu                            # rectify the saved images
    pytest -m hardware --save-images regression_results  # keep a PNG of every case
    pytest -m "not hardware"                             # only the simulator-free tests

--sizes applies to the directed cases whose subject is not geometry. The frame
size edges and the rounding ties keep their own sizes, and the randomised cases
pick theirs from the seed. --relu only changes what is saved: ReLU collapses
negatives, so a verdict taken after it could call two different frames equal.
"""

from __future__ import annotations

import shutil
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import TYPE_CHECKING

import numpy as np
import pytest

from conv_lab.core.images import PATTERNS, generate_pattern
from conv_lab.core.kernels import PRESETS, Kernel, preset
from conv_lab.core.rendering import save_grid
from conv_lab.hardware import QuestaTestbench, TestbenchError
from conv_lab.harness import Harness

if TYPE_CHECKING:
    from conftest import Gallery

pytestmark = pytest.mark.hardware

ARTIFACTS = ("stimulus.txt", "features.txt", "sim.log")

Verify = Callable[[np.ndarray, Sequence[Kernel]], None]


# --------------------------------------------------------------------------- #
# Fixtures and the per-case check
# --------------------------------------------------------------------------- #

@pytest.fixture(scope="session")
def questa(tmp_path_factory: pytest.TempPathFactory) -> QuestaTestbench:
    if shutil.which("vsim") is None:
        pytest.skip("QuestaSim not on PATH (no vsim): hardware regression skipped")
    return QuestaTestbench(tmp_path_factory.mktemp("questa"))


@pytest.fixture(scope="session")
def harness(questa: QuestaTestbench) -> Harness:
    return Harness(questa)


@pytest.fixture
def verify(harness: Harness, questa: QuestaTestbench, gallery: Gallery | None,
           request: pytest.FixtureRequest, tmp_path: Path) -> Verify:
    """check() bound to this test: its name, its tmp directory, the gallery and --relu."""
    relu = request.config.getoption("relu")

    def _verify(image: np.ndarray, kernels: Sequence[Kernel]) -> None:
        check(harness, image, kernels, run_dir=questa.run_dir, case=request.node.name,
              keep=tmp_path, gallery=gallery, relu=relu)
    return _verify


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    config = metafunc.config
    if "seed" in metafunc.fixturenames:
        seeds = range(config.getoption("seeds"))
        metafunc.parametrize("seed", seeds, ids=[f"seed{s}" for s in seeds])
    if "size" in metafunc.fixturenames:
        sizes = config.getoption("sizes")
        metafunc.parametrize("size", sizes, ids=[f"{s}px" for s in sizes])


def check(harness: Harness, image: np.ndarray, kernels: Sequence[Kernel], *, run_dir: Path,
          case: str, keep: Path, gallery: Gallery | None, relu: bool) -> None:
    """Run one frame through the harness and require every lane to match bit for bit."""
    size, window = image.shape[0], kernels[0].size
    geometry = f"{f'{size}x{size}':>7}  {window}x{window}  {len(kernels):>2} kernel(s)"

    try:
        run = harness.run(image, kernels)
    except TestbenchError as exc:
        _preserve(run_dir, keep)
        if gallery is not None:
            gallery.record(case, "ERROR", geometry, details=str(exc).splitlines()[:1])
        raise

    failures = run.comparison.failures()                 # always from the raw frames
    shown = run.comparison.rectified() if relu else run.comparison

    if gallery is not None:
        gallery.record(case, "FAIL" if failures else "PASS", geometry,
                       rows=shown.grid_rows(), details=failures)

    if failures:
        _preserve(run_dir, keep)
        save_grid(shown.grid_rows(mismatched_only=True), keep / "mismatch.png")
        pytest.fail(
            f"{len(failures)} of {len(kernels)} lane(s) disagree on a {size}x{size} frame "
            f"(artifacts: {keep})\n  " + "\n  ".join(failures),
            pytrace=False,
        )


def _preserve(run_dir: Path, keep: Path) -> None:
    """The run directory is shared, so the next case would overwrite the evidence."""
    for name in ARTIFACTS:
        if (run_dir / name).is_file():
            shutil.copy2(run_dir / name, keep / name)


def random_kernel(rng: np.random.Generator, name: str, size: int = 3) -> Kernel:
    weights = rng.integers(-128, 128, size=(size, size))
    return Kernel(name, tuple(tuple(int(w) for w in row) for row in weights))


def noise(size: int, seed: int) -> np.ndarray:
    return generate_pattern("noise", size, seed=seed)


# --------------------------------------------------------------------------- #
# Directed cases
# --------------------------------------------------------------------------- #

@pytest.mark.parametrize("pattern", PATTERNS)
def test_every_preset_on_every_pattern(verify: Verify, pattern, size):
    """All presets as parallel lanes of one frame, once per synthetic pattern."""
    verify(generate_pattern(pattern, size, seed=1), list(PRESETS.values()))


@pytest.mark.parametrize("edge", [4, 5, 7, 8, 16, 17, 31, 32, 33, 64])
def test_frame_size(verify: Verify, edge):
    """Geometry edges, independent of --sizes. 4 is the smallest legal frame (output
    FIFO depth 2); 16 and 32 exactly fill the line buffer's $clog2 column counter,
    17 and 33 need one bit more; the odd sizes are not powers of two."""
    rng = np.random.default_rng(edge)
    kernels = [preset("sobel_x"), preset("laplacian_8"), preset("gaussian_blur"),
               random_kernel(rng, "random")]
    verify(noise(edge, seed=edge), kernels)


@pytest.mark.parametrize("weight", [16, -128], ids=["plus16", "minus128"])
def test_every_tap_position(verify: Verify, weight, size):
    """Nine one-hot kernels, one per tap. Each lane's output is the input shifted to
    that tap's offset, so a column mirror or row swap in the tap order lands a lane
    on the wrong shift - the asymmetry no symmetric preset can expose."""
    kernels = [
        Kernel(f"tap_r{r}c{c}", tuple(tuple(weight if (i, j) == (r, c) else 0
                                           for j in range(3)) for i in range(3)))
        for r in range(3) for c in range(3)
    ]
    verify(noise(size, seed=3), kernels)


EXTREME_KERNELS = [
    Kernel("all_max", ((127,) * 3,) * 3),
    Kernel("all_min", ((-128,) * 3,) * 3),
    Kernel("alternating", tuple(tuple(127 if (i + j) % 2 == 0 else -128 for j in range(3))
                                for i in range(3))),
    preset("identity"),
]


def _extreme_image(kind: str, size: int) -> np.ndarray:
    rows, cols = np.indices((size, size))
    match kind:
        case "black":
            return np.zeros((size, size), dtype=np.uint8)
        case "white":
            return np.full((size, size), 255, dtype=np.uint8)
        case "pixel_checker":
            return np.where((rows + cols) % 2 == 0, 255, 0).astype(np.uint8)
        case _:
            return noise(size, seed=11)


@pytest.mark.parametrize("image_kind", ["black", "white", "pixel_checker", "noise"])
def test_extreme_pixels_and_weights(verify: Verify, image_kind, size):
    """The limits of the datapath. all_max and all_min on a white frame reach the
    largest positive and negative sums the accumulator ever holds (+-9 * 255 * 128);
    a pixel checkerboard against the alternating kernel flips the sign of the sum on
    every step of the window."""
    verify(_extreme_image(image_kind, size), EXTREME_KERNELS)


def test_round_half_up_ties(verify: Verify):
    """Every pixel value 0..255 through a centre tap of +-1, +-3 and +-7.

    Each output is weight * pixel >> 4, rounded half up. With odd weights every
    residue mod 16 appears for both signs, including every exact .5 tie - the
    positive ties with an even quotient are where round-half-up and
    round-half-to-even disagree, the negative ties are where round-half-up and
    round-half-away-from-zero disagree. The frame is fixed at 18x18: exactly one
    16x16 output per pixel value."""
    image = np.zeros((18, 18), dtype=np.uint8)
    image[1:17, 1:17] = np.arange(256, dtype=np.uint8).reshape(16, 16)
    kernels = [Kernel(f"centre_{w:+d}", ((0, 0, 0), (0, w, 0), (0, 0, 0)))
               for w in (1, -1, 3, -3, 7, -7)]
    verify(image, kernels)


@pytest.mark.parametrize("count", [1, 2, 3, 4, 5, 7, 8, 9, 16])
def test_lane_count(verify: Verify, count, size):
    """NUM_KERNELS across the select bus's width steps. The bus is $clog2(N)+1 bits,
    so its width changes at 2, 3, 5 and 9; distinct random kernels make any lane
    crossing visible."""
    rng = np.random.default_rng(100 + count)
    kernels = [random_kernel(rng, f"lane{i}") for i in range(count)]
    verify(noise(size, seed=count), kernels)


@pytest.mark.parametrize("window", [5, 7])
def test_window_size(verify: Verify, window, size):
    """WINDOW_SIZE is a parameter, but every other directed case drives 3x3. A larger
    window changes the MAC architecture conv_system builds (5x5 and 7x7 use the row
    chains instead of the 3x3 single chain), DROP, the line buffer's row count and
    the output FIFO's depth all at once."""
    if size <= window:
        pytest.skip(f"a {size}x{size} frame is too small for a {window}x{window} window")
    rng = np.random.default_rng(window)
    kernels = [random_kernel(rng, f"random{i}", window) for i in range(3)]
    verify(noise(size, seed=window), kernels)


# --------------------------------------------------------------------------- #
# Randomised cases
# --------------------------------------------------------------------------- #

def test_randomised(verify: Verify, seed):
    """Random geometry, image and lanes, reproducible from the seed in the test id."""
    rng = np.random.default_rng(seed)
    window = int(rng.choice([3, 3, 3, 5]))
    size = int(rng.integers(window + 1, 49))
    if rng.random() < 0.25:
        image = generate_pattern(str(rng.choice(PATTERNS)), size, seed=seed)  # type: ignore[arg-type]
    else:
        image = rng.integers(0, 256, size=(size, size), dtype=np.uint8)
    kernels = [random_kernel(rng, f"r{i}", window) for i in range(int(rng.integers(1, 7)))]
    verify(image, kernels)
