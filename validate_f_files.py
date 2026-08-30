#!/usr/bin/env python3
"""Validate all .f file paths in the project."""

import unicodedata
from pathlib import Path

BOX_WIDTH = 78  # inner width, between the two vertical borders

# Characters that count as len()==1 but render as 2 terminal columns.
_WIDE_OVERRIDES = {"✅"}


def display_width(text: str) -> int:
    """Best-effort terminal column width of text (handles wide emoji)."""
    width = 0
    for ch in text:
        if ch in _WIDE_OVERRIDES or unicodedata.east_asian_width(ch) in ("W", "F"):
            width += 2
        else:
            width += 1
    return width


def box_top():
    print("╔" + "═" * BOX_WIDTH + "╗")


def box_divider():
    print("╠" + "═" * BOX_WIDTH + "╣")


def box_bottom():
    print("╚" + "═" * BOX_WIDTH + "╝")


def box_line(text: str = "") -> None:
    """Print one line inside the box, padded/truncated to fit BOX_WIDTH columns."""
    width = display_width(text)
    if width > BOX_WIDTH:
        # Truncate by characters (rough), then re-check/pad.
        while text and display_width(text) > BOX_WIDTH - 1:
            text = text[:-1]
        text += "…"
        width = display_width(text)
    print("║" + text + " " * (BOX_WIDTH - width) + "║")


def box_title(text: str) -> None:
    width = display_width(text)
    left = (BOX_WIDTH - width) // 2
    right = BOX_WIDTH - width - left
    print("║" + " " * left + text + " " * right + "║")


def find_missing_refs(f_file: Path):
    """Return a list of (line_num, ref_path, resolved_path) for missing references."""
    f_dir = f_file.parent
    missing = []

    with open(f_file, "r") as fh:
        lines = fh.readlines()

    for line_num, raw_line in enumerate(lines, 1):
        line = raw_line.strip()
        if not line or line.startswith("+incdir"):
            continue

        ref_path = line[3:].strip() if line.startswith("-F ") else line
        if not ref_path or ref_path.startswith("+"):
            continue

        full_path = (f_dir / ref_path).resolve()
        if not full_path.exists():
            try:
                display_path = str(full_path.relative_to(Path.cwd()))
            except ValueError:
                display_path = str(full_path)
            missing.append((line_num, ref_path, display_path))

    return missing


def validate_f_files():
    f_files = sorted(Path(".").rglob("*.f"))
    total = len(f_files)

    results = {f_file: find_missing_refs(f_file) for f_file in f_files}
    files_with_issues = [f for f, missing in results.items() if missing]
    valid = total - len(files_with_issues)

    box_top()
    box_title("COMPREHENSIVE .F FILE VALIDATION REPORT")
    box_divider()
    box_line()
    box_line(f"  Total .f files found: {total}")
    box_line(f"  Valid files:          {valid}")
    box_line(f"  Files with issues:    {len(files_with_issues)}")
    box_line()

    if files_with_issues:
        box_divider()
        box_line(" ISSUES DETECTED:")
        box_divider()

        for f_file in files_with_issues:
            box_line()
            box_line(f" {f_file}")
            for line_num, ref_path, display_path in results[f_file]:
                box_line(f"   Line {line_num}: ✗ {ref_path}")
                box_line(f"         → {display_path}")
    else:
        box_line()
        box_line("  ✅  ALL FILES VALIDATED SUCCESSFULLY!")
        box_line()

    box_bottom()


if __name__ == "__main__":
    validate_f_files()