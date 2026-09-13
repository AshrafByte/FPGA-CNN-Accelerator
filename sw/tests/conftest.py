"""pytest wiring shared by tests/unit and tests/regression: options and the image gallery."""

from __future__ import annotations

import re
from collections import Counter
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import numpy as np
import pytest

from conv_lab.core.rendering import save_grid


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption(
        "--seeds", type=int, default=20, metavar="N",
        help="randomised cases in the hardware regression (default: 20)",
    )
    parser.addoption(
        "--save-images", type=Path, default=None, metavar="DIR",
        help="keep a comparison PNG of every hardware regression case, plus "
             "summary.txt, in DIR/run-<timestamp>/",
    )


@dataclass(slots=True)
class Gallery:
    """--save-images: one PNG per regression case and a running summary.txt.

    Each pytest session writes to its own run-<timestamp> folder, so an earlier
    run is never overwritten or deleted and no folder mixes two runs. The summary
    is rewritten after every case, so it stays complete up to the last finished
    case even if the session is interrupted.
    """

    folder: Path
    started: datetime
    lines: list[str] = field(default_factory=list)
    counts: Counter[str] = field(default_factory=Counter)

    def record(self, case: str, status: str, geometry: str, *,
               rows: Sequence[Sequence[tuple[str, np.ndarray]]] = (),
               details: Sequence[str] = ()) -> None:
        self.folder.mkdir(parents=True, exist_ok=True)
        image = ""
        if rows:
            image = _file_name(case)
            save_grid(rows, self.folder / image)
        self.counts[status] += 1
        self.lines.append(f"{status:<5}  {case:<48}  {geometry}  {image}".rstrip())
        self.lines += [f"       {line}" for line in details]
        self._write_summary()

    def _write_summary(self) -> None:
        header = [
            f"conv_lab hardware regression, started {self.started:%Y-%m-%d %H:%M:%S}",
            f"{sum(self.counts.values())} case(s): {self.counts['PASS']} passed, "
            f"{self.counts['FAIL']} failed, {self.counts['ERROR']} errored",
            "",
        ]
        (self.folder / "summary.txt").write_text("\n".join(header + self.lines) + "\n",
                                                  encoding="utf-8")


def _file_name(case: str) -> str:
    """test_frame_size[33] -> test_frame_size-33.png"""
    return re.sub(r"[^\w.-]+", "_", case.replace("[", "-").replace("]", "")) + ".png"


GALLERY = pytest.StashKey[Gallery]()


@pytest.fixture(scope="session")
def gallery(request: pytest.FixtureRequest) -> Gallery | None:
    root = request.config.getoption("save_images")
    if root is None:
        return None
    started = datetime.now()
    found = Gallery(root.resolve() / f"run-{started:%Y%m%d-%H%M%S}", started)
    request.config.stash[GALLERY] = found
    return found


def pytest_terminal_summary(terminalreporter: pytest.TerminalReporter,
                            config: pytest.Config) -> None:
    found = config.stash.get(GALLERY, None)
    if found is not None and found.lines:
        terminalreporter.write_line(f"regression images and summary: {found.folder}")
