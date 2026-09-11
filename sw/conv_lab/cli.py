"""Command line front end: image in, kernel picked, testbench run, result shown."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

from . import display, reference
from .imaging import (
    ImageError,
    PATTERNS,
    generate_pattern,
    load_image,
    normalise,
    save_comparison,
    validate_dimensions,
)
from .kernels import PRESETS, Kernel, KernelError, preset
from .testbench import TestbenchError, run


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="conv_lab",
        description=(
            "Convolve a grayscale image on the conv_system SystemVerilog testbench "
            "under QuestaSim and check the result against a bit-accurate model. "
            "Pass --reference to compute in Python instead, with no simulator. "
            "Run with no arguments for an interactive session."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "examples:\n"
            "  conv_lab                                   interactive\n"
            "  conv_lab --image cat.png --size 64 --kernel sobel_x\n"
            "  conv_lab --pattern circle --size 32 --kernel sobel_x --kernel sobel_y\n"
            "  conv_lab --pattern ramp --size 16 --weights '1 0 -1; 2 0 -2; 1 0 -1'\n"
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
                        help="compute in Python with the reference model instead of "
                             "running the Questa testbench; needs no simulator")
    parser.add_argument("--png", type=Path, metavar="PATH",
                        help="also write the side-by-side comparison as a PNG")
    parser.add_argument("--csv", type=Path, metavar="PATH",
                        help="write raw feature values as CSV (one file per kernel)")
    parser.add_argument("--run-dir", type=Path, help="where to keep simulator artifacts")
    parser.add_argument("--list-kernels", action="store_true", help="show the presets and exit")
    parser.add_argument("--verbose", action="store_true", help="echo the simulator commands")
    return parser


# --------------------------------------------------------------------------- #
# Interactive prompts
# --------------------------------------------------------------------------- #

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


def gather_interactive(default_size: int) -> tuple[np.ndarray, list[Kernel]]:
    print(display.rule("conv_lab: convolution on the conv_system testbench"))
    kernels = _prompt_kernels()
    print()
    image = _prompt_image(kernels[0].size, default_size)
    return image, kernels


# --------------------------------------------------------------------------- #
# Assembling from flags
# --------------------------------------------------------------------------- #

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


# --------------------------------------------------------------------------- #
# Compute paths
# --------------------------------------------------------------------------- #

def run_testbench(image: np.ndarray, kernels: list[Kernel],
                  args: argparse.Namespace) -> tuple[np.ndarray, int, str]:
    result = run(image, kernels, run_dir=args.run_dir, echo=args.verbose)
    footer = (
        f"Questa elaborated conv_system at INPUT_SIZE={image.shape[0]}, "
        f"WINDOW_SIZE={kernels[0].size}, NUM_KERNELS={len(kernels)} "
        f"in {result.elapsed_s:.1f}s   (artifacts: {result.run_dir})"
    )
    return result.features, result.drop_bits, footer


def run_reference(image: np.ndarray, kernels: list[Kernel]) -> tuple[np.ndarray, int, str]:
    """Compute in Python only - same arithmetic as the hardware, no simulator.

    The frames are identical to what conv_system would emit, since the model is
    bit-accurate; what is missing is any evidence that the RTL agrees. Nothing
    here has been near the DUT, so the output is labelled as the model's and no
    MATCH verdict is printed.
    """
    drop = reference.drop_bits(kernels[0].size)
    features = np.stack([reference.convolve(image, kernel) for kernel in kernels])
    footer = (
        f"Python reference model, no simulator: signed MAC -> round-half-to-even "
        f">>{drop} -> saturate,\nmodelling conv_system at INPUT_SIZE={image.shape[0]}, "
        f"WINDOW_SIZE={kernels[0].size}, NUM_KERNELS={len(kernels)}. "
        f"Nothing here was checked against the RTL."
    )
    return features, drop, footer


# --------------------------------------------------------------------------- #
# Reporting
# --------------------------------------------------------------------------- #

def report(image: np.ndarray, kernels: list[Kernel], features: np.ndarray, drop: int,
           args: argparse.Namespace, *, verify: bool, footer: str) -> bool:
    """Print the kernel cards, the previews and the footer.

    `verify` says where `features` came from. From the testbench, they get
    checked against the model and the verdict is the return value. From the
    model itself there is no second opinion to compare against, so the frames
    are simply reported as what they are.
    """
    all_match = True
    panels: dict[str, np.ndarray] = {"input": image}

    for index, kernel in enumerate(kernels):
        frame = features[index]
        panels[kernel.name] = frame

        print()
        print(display.rule(f"kernel {index}: {kernel.name}"))
        print(display.kernel_card(kernel, drop))
        print()

        if verify:
            golden = reference.convolve(image, kernel)
            verdict = display.compare(frame, golden)
            all_match &= verdict.exact
            print(f"  hardware   {display.stats(frame)}")
            print(f"  model      {display.stats(golden)}")
            print(f"  {verdict.summary()}")
        else:
            print(f"  model      {display.stats(frame)}")

        if args.csv:
            path = _csv_path(args.csv, kernel.name, len(kernels))
            np.savetxt(path, frame, fmt="%d", delimiter=",")
            print(f"  csv        {path}")

    print()
    print(display.rule("input vs output"))
    print(display.side_by_side(panels))

    if args.png:
        written = save_comparison(image, {k.name: normalise(features[i])
                                          for i, k in enumerate(kernels)}, args.png)
        print(f"\nwrote {written}")

    print()
    print(display.rule())
    print(footer)
    return all_match


def _csv_path(base: Path, kernel_name: str, count: int) -> Path:
    if count == 1:
        return base
    return base.with_name(f"{base.stem}_{kernel_name}{base.suffix or '.csv'}")


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #

def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.list_kernels:
        for name, k in PRESETS.items():
            gain = k.hardware_gain(reference.drop_bits(k.size))
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

        where = "reference model" if args.reference else "testbench"
        print(f"\nrunning the {where} on a {image.shape[1]}x{image.shape[0]} frame "
              f"with {len(kernels)} kernel(s)...")

        if args.reference:
            features, drop, footer = run_reference(image, kernels)
        else:
            features, drop, footer = run_testbench(image, kernels, args)
    except (ImageError, KernelError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except TestbenchError as exc:
        print(f"testbench error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\naborted", file=sys.stderr)
        return 130

    matched = report(image, kernels, features, drop, args,
                     verify=not args.reference, footer=footer)
    return 0 if matched else 1


if __name__ == "__main__":
    raise SystemExit(main())
