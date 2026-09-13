"""Argument parsing and main(): resolve the inputs, run the harness, print the report."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

from ..core.images import PATTERNS, ImageError, generate_pattern, load_image, validate_dimensions
from ..core.kernels import PRESETS, Kernel, KernelError, preset
from ..core.reference import drop_bits
from ..hardware import QuestaTestbench, TestbenchError
from ..harness import Harness
from .prompts import gather_interactive
from .report import report


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="conv_lab",
        description=(
            "Run a grayscale image through the conv_system SystemVerilog testbench "
            "under QuestaSim and through the Python reference model in one go, show "
            "both results side by side, and check they agree bit for bit. Pass "
            "--reference to skip the simulator. Run with no arguments for an "
            "interactive session."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "examples:\n"
            "  conv_lab                                   interactive\n"
            "  conv_lab --image cat.png --size 64 --kernel sobel_x --png compare.png\n"
            "  conv_lab --pattern circle --size 32 --kernel sobel_x --kernel sobel_y\n"
            "  conv_lab --pattern ramp --size 16 --weights '1 0 -1; 2 0 -2; 1 0 -1'\n"
            "  conv_lab --image cat.png --size 64 --kernel sobel_x --reference --relu\n"
        ),
    )

    source = parser.add_mutually_exclusive_group()
    source.add_argument("--image", type=Path, help="image file; any format Pillow reads")
    source.add_argument("--pattern", choices=PATTERNS, help="use a synthetic frame instead")

    parser.add_argument("--size", type=int, default=32,
                        help="frame is resized to SIZE x SIZE (default: 32)")
    parser.add_argument("--kernel", action="append", default=[], metavar="NAME",
                        help=f"preset kernel, repeatable; one of: {', '.join(PRESETS)}")
    parser.add_argument("--weights", action="append", default=[], metavar="TEXT",
                        help="custom kernel, repeatable, e.g. '1 0 -1; 2 0 -2; 1 0 -1'")
    parser.add_argument("--reference", action="store_true",
                        help="skip the Questa testbench and show only the reference "
                             "model; needs no simulator")
    parser.add_argument("--relu", action="store_true",
                        help="apply max(0, x) to what is shown and saved, as a CNN layer "
                             "would; the hardware-vs-reference check always runs on "
                             "raw features")
    parser.add_argument("--png", type=Path, metavar="PATH",
                        help="write input | hardware | reference as a PNG, one row per kernel")
    parser.add_argument("--csv", type=Path, metavar="PATH",
                        help="write feature values as CSV, one file per kernel and source")
    parser.add_argument("--run-dir", type=Path, help="where to keep simulator artifacts")
    parser.add_argument("--list-kernels", action="store_true", help="show the presets and exit")
    parser.add_argument("--verbose", action="store_true", help="echo the simulator commands")
    return parser


def resolve_kernels(args: argparse.Namespace) -> list[Kernel]:
    kernels = [preset(name) for name in args.kernel]
    kernels += [
        Kernel.parse(text, name=f"custom_{i}" if len(args.weights) > 1 else "custom")
        for i, text in enumerate(args.weights, start=1)
    ]
    return kernels


def resolve_image(args: argparse.Namespace, window: int) -> np.ndarray:
    validate_dimensions(args.size, args.size, window)
    if args.image:
        return load_image(args.image, args.size)
    return generate_pattern(args.pattern or "ramp", args.size)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.list_kernels:
        for name, k in PRESETS.items():
            gain = k.hardware_gain(drop_bits(k.size))
            print(f"{name:<16} sum {k.weight_sum:>5}  gain {gain:>6.3f}   {k.description}")
        return 0

    interactive = not (args.kernel or args.weights or args.image or args.pattern)

    try:
        if interactive:
            image, kernels = gather_interactive(args.size)
        else:
            kernels = resolve_kernels(args)
            if not kernels:
                print("error: pass --kernel and/or --weights, or run with no arguments "
                      "for the interactive flow", file=sys.stderr)
                return 2
            image = resolve_image(args, kernels[0].size)

        where = "the reference model" if args.reference else "the testbench and the reference model"
        print(f"\nrunning {where} on a {image.shape[1]}x{image.shape[0]} frame "
              f"with {len(kernels)} kernel(s)...")

        testbench = None if args.reference else QuestaTestbench(args.run_dir, echo=args.verbose)
        run = Harness(testbench).run(image, kernels)
    except (ImageError, KernelError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except TestbenchError as exc:
        print(f"testbench error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\naborted", file=sys.stderr)
        return 130

    return 0 if report(run, args) else 1
