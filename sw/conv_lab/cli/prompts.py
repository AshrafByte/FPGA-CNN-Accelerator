"""The interactive flow used when conv_lab is run with no input flags."""

from __future__ import annotations

import numpy as np

from ..core.images import PATTERNS, ImageError, generate_pattern, load_image, validate_dimensions
from ..core.kernels import PRESETS, Kernel, KernelError, preset
from . import terminal


def gather_interactive(default_size: int) -> tuple[np.ndarray, list[Kernel]]:
    print(terminal.rule("conv_lab: convolution on the conv_system testbench"))
    kernels = _prompt_kernels()
    print()
    image = _prompt_image(kernels[0].size, default_size)
    return image, kernels


def _ask(prompt: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    try:
        answer = input(f"{prompt}{suffix}: ").strip()
    except EOFError:
        raise SystemExit("\naborted") from None
    return answer or default


def _prompt_image(window: int, default_size: int) -> np.ndarray:
    while True:
        try:
            size = int(_ask("Frame size (square, e.g. 32)", str(default_size)))
            validate_dimensions(size, size, window)

            print(f"\n  Source: a file, or a synthetic pattern ({', '.join(PATTERNS)})")
            answer = _ask("  Image path, or pattern name", "ramp")
            if answer in PATTERNS:
                return generate_pattern(answer, size)  # type: ignore[arg-type]
            return load_image(answer, size)
        except (ImageError, ValueError) as exc:
            print(f"  ! {exc}\n")


def _prompt_kernels() -> list[Kernel]:
    print("\n  Presets:")
    for name, k in PRESETS.items():
        print(f"    {name:<16} {k.description}")
    print("\n  Enter preset name(s) separated by commas, or 'custom' to type weights.")

    while True:
        answer = _ask("  Kernel", "sobel_x")
        try:
            if answer.lower() == "custom":
                print("  Rows separated by ';' or newline, e.g. 1 0 -1; 2 0 -2; 1 0 -1")
                return [Kernel.parse(_ask("  Weights"))]
            return [preset(name.strip()) for name in answer.split(",") if name.strip()]
        except KernelError as exc:
            print(f"  ! {exc}\n")
