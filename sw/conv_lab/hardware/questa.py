"""The QuestaSim commands for one frame, and the shell that runs them.

Questa (vlib / vlog / vsim) is the only supported simulator.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from collections.abc import Sequence
from pathlib import Path
from typing import Final

from .contract import TestbenchError

REPO_ROOT: Final = Path(__file__).resolve().parents[3]
MANIFEST: Final = REPO_ROOT / "hw" / "system" / "conv_system" / "sim" / "compile.f"
TOP: Final = "conv_image_tb"

#: Simulation gets slow long before it gets wrong; this is a stall guard.
TIMEOUT_S: Final = 1800


def commands(run_dir: Path, input_size: int, window: int, num_kernels: int, *,
             recompile: bool = True) -> list[str]:
    """The vlib/vlog/vsim sequence for one frame, run from `run_dir`.

    `recompile=False` drops vlog and reuses the library already built in
    `run_dir`. Only elaboration depends on the geometry, so a session that runs
    many frames against unchanged RTL needs to compile exactly once.
    """
    if shutil.which("vsim") is None:
        raise TestbenchError(
            "Questa not found on PATH (no vsim). Install it, or pass --reference "
            "to compute with the Python model instead."
        )
    generics = " ".join(
        f"-g{name}={value}"
        for name, value in (("INPUT_SIZE", input_size),
                            ("WINDOW_SIZE", window),
                            ("NUM_KERNELS", num_kernels))
    )
    # Whether the library already exists is decided here rather than with a
    # shell conditional: cmd.exe binds `&&` inside an `if`, so `if not exist
    # work vlib work && vlog ...` would swallow the whole rest of the chain on
    # every run after the first.
    steps = [] if (run_dir / "work").is_dir() else ["vlib work"]

    # No source file carries a `timescale directive, so pin one rather than
    # inheriting whatever the local modelsim.ini happens to set as Resolution.
    if recompile:
        steps.append(f'vlog -sv -quiet -timescale 1ns/1ps -F "{MANIFEST}"')
    steps.append(
        f'vsim -c {generics} work.{TOP} '
        f'+stim=stimulus.txt +result=features.txt -do "run -all; quit -f"'
    )
    return steps


def execute(steps: Sequence[str], *, cwd: Path, echo: bool) -> str:
    """Run the steps as one shell session, stopping at the first failure; return the log."""
    if os.name == "nt":
        command = " && ".join(steps)
        executable = None
    else:
        # set -e gives the same stop-on-first-failure that cmd's && chain does.
        command = "set -e\n" + "\n".join(steps)
        executable = "/bin/bash"

    if echo:
        for step in steps:
            print(f"    $ {step}")

    try:
        proc = subprocess.run(
            command,
            cwd=cwd,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=TIMEOUT_S,
            shell=True,
            executable=executable,
        )
    except subprocess.TimeoutExpired as exc:
        raise TestbenchError(f"simulation exceeded {TIMEOUT_S}s and was killed") from exc

    return proc.stdout + proc.stderr
