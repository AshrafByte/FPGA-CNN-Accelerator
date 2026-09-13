"""The folders are the architecture, so the import direction between them is tested.

    core      imports nothing else from conv_lab
    hardware  may import core
    harness   may import core and hardware
    cli       may import core, hardware and harness

On top of that, hardware never imports the reference model or the comparison: the
two sides of a run only meet in harness.py. An import that breaks either rule
fails here instead of quietly tangling the layers.
"""

from __future__ import annotations

import ast
from pathlib import Path

import pytest

import conv_lab

PACKAGE = Path(conv_lab.__file__).parent

ALLOWED = {
    "core": set(),
    "hardware": {"core"},
    "harness": {"core", "hardware"},
    "cli": {"core", "hardware", "harness"},
}

HARDWARE_MUST_NOT_SEE = {"conv_lab.core.reference", "conv_lab.core.comparison"}


def _module_name(path: Path) -> str:
    parts = list(path.relative_to(PACKAGE.parent).with_suffix("").parts)
    if parts[-1] == "__init__":
        parts.pop()
    return ".".join(parts)


def _layer(module: str) -> str | None:
    """conv_lab.hardware.questa -> 'hardware'; conv_lab.harness -> 'harness'."""
    parts = module.split(".")
    return parts[1] if parts[0] == "conv_lab" and len(parts) > 1 else None


def _imports(path: Path) -> set[str]:
    """Every conv_lab module a file imports, with relative imports resolved."""
    name = _module_name(path)
    package = name if path.name == "__init__.py" else name.rpartition(".")[0]
    found: set[str] = set()
    for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
        if isinstance(node, ast.Import):
            found.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            if node.level:
                base = package.split(".")
                base = base[: len(base) - (node.level - 1)]
                if node.module:
                    found.add(".".join([*base, node.module]))
                else:
                    found.update(".".join([*base, alias.name]) for alias in node.names)
            elif node.module:
                found.add(node.module)
    return {module for module in found if module.startswith("conv_lab")}


LAYERED = [path for path in sorted(PACKAGE.rglob("*.py")) if _layer(_module_name(path)) in ALLOWED]


@pytest.mark.parametrize("path", LAYERED, ids=lambda p: p.relative_to(PACKAGE).as_posix())
def test_imports_follow_the_layer_order(path):
    layer = _layer(_module_name(path))
    allowed = ALLOWED[layer] | {layer}
    offending = sorted(module for module in _imports(path) if _layer(module) not in allowed)
    assert not offending, f"{layer} may only import {sorted(allowed)}, but imports {offending}"


def test_the_hardware_side_never_sees_the_reference_side():
    for path in sorted((PACKAGE / "hardware").rglob("*.py")):
        leaked = sorted(_imports(path) & HARDWARE_MUST_NOT_SEE)
        assert not leaked, f"{path.name} imports {leaked}; hardware and reference meet only in harness.py"


def test_every_module_sits_in_a_layer():
    """A new top-level module has to be placed in the order on purpose."""
    loose = sorted(path.name for path in PACKAGE.glob("*.py")
                   if path.stem not in {"__init__", "__main__", *ALLOWED})
    assert not loose, f"modules outside the layer map: {loose}"
