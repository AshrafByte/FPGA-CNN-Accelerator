#!/usr/bin/env python3
"""
generate_uvm_env.py — One-shot UVM environment generator.
Refactored for Object-Oriented readability, maintainability, and extensibility.
"""

import argparse
import fnmatch
import json
import re
import shutil
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional, List, Tuple, Set


# ═════════════════════════════════════════════════════════════════════════
# MODELS & CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════

@dataclass(slots=True)
class Port:
    name: str
    direction: str
    data_type: str
    width: int
    dimensions: str

    @property
    def range(self) -> str:
        if self.dimensions:
            return self.dimensions
        return "" if self.width <= 1 else f"[{self.width - 1}:0]"


@dataclass
class GeneratorConfig:
    dut_ref: str
    target: str
    template_dir: Path
    output_dir: Path
    exclude: Set[str]
    overwrite: bool
    dump_ports: Optional[Path]
    repo_root: Path


class Logger:
    @staticmethod
    def info(msg: str):
        print(f"[INFO]  {msg}")

    @staticmethod
    def warn(msg: str):
        print(f"[WARN]  {msg}")

    @staticmethod
    def error(msg: str):
        print(f"[ERROR] {msg}", file=sys.stderr)

    @staticmethod
    def success(msg: str):
        print(f"[DONE]  {msg}")

    @staticmethod
    def step(msg: str):
        print(f"--- {msg} ---")


# ═════════════════════════════════════════════════════════════════════════
# FILE RESOLUTION
# ═════════════════════════════════════════════════════════════════════════

class FilelistResolver:
    RTL_EXTENSIONS = {".sv", ".v"}
    IGNORED_FILELISTS = {"tb.f", "dv.f", "uvc.f"}

    def __init__(self, repo_root: Path):
        self.repo_root = repo_root

    def resolve_dut(self, dut_ref: str) -> Path:
        candidate = Path(dut_ref).resolve()
        if candidate.is_file():
            return candidate

        dut_name = dut_ref.strip()
        hw_root = self.repo_root / "hw"
        matches: List[Path] = []

        for path in hw_root.rglob("*"):
            if path.is_file() and path.stem == dut_name and path.suffix.lower() in self.RTL_EXTENSIONS:
                matches.append(path)

        if not matches:
            raise FileNotFoundError(
                f"Could not resolve DUT '{dut_ref}' under {hw_root}. "
                f"Pass the RTL file path explicitly if it lives elsewhere."
            )

        # Sort by shortest path depth
        matches.sort(key=lambda p: (len(p.parts), len(str(p))))
        return matches[0]

    def find_sim_filelists(self, rtl_path: Path) -> Tuple[Path, Path, Path]:
        current = rtl_path.parent.resolve()

        while current != current.parent:
            sim_dir = current / "sim"
            compile_f = sim_dir / "compile.f"
            design_f = sim_dir / "design.f"
            
            if compile_f.is_file() and design_f.is_file():
                return sim_dir, compile_f, design_f
            current = current.parent

        raise FileNotFoundError(
            f"Could not find a sibling sim/compile.f + sim/design.f for {rtl_path}."
        )

    def _parse_line(self, line: str) -> str:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("//"):
            return ""
        return stripped

    def _should_keep_source(self, path: Path) -> bool:
        try:
            rel_path = path.resolve().relative_to(self.repo_root).as_posix()
            return rel_path.startswith("hw/") or rel_path.startswith("common/packages/")
        except ValueError:
            return False

    def collect_sources(self, filelist_path: Path) -> Tuple[List[Path], List[Path]]:
        source_files: List[Path] = []
        include_dirs: List[Path] = []
        visited: Set[Path] = set()

        def _visit(path: Path) -> None:
            abs_path = path.resolve()
            if abs_path in visited:
                return
            visited.add(abs_path)

            if abs_path.name in self.IGNORED_FILELISTS:
                return

            base_dir = abs_path.parent
            with abs_path.open("r", encoding="utf-8") as f:
                for raw_line in f:
                    line = self._parse_line(raw_line)
                    if not line:
                        continue

                    if line.startswith("+incdir+"):
                        for part in line.split("+incdir+")[1:]:
                            if part:
                                include_dirs.append((base_dir / part).resolve())
                        continue

                    if line.startswith("-F ") or line.startswith("-f "):
                        nested = line.split(None, 1)[1].strip()
                        _visit(base_dir / nested)
                        continue

                    if line.endswith(".f"):
                        _visit(base_dir / line)
                        continue

                    if Path(line).suffix.lower() in self.RTL_EXTENSIONS or line.endswith(".svh"):
                        source_file = (base_dir / line).resolve()
                        if self._should_keep_source(source_file):
                            source_files.append(source_file)

        _visit(filelist_path)
        return source_files, include_dirs


# ═════════════════════════════════════════════════════════════════════════
# PORT EXTRACTION
# ═════════════════════════════════════════════════════════════════════════

class RTLPortExtractor:
    def __init__(self, target_module: str):
        self.target_module = target_module

    class _PortVisitor:
        def __init__(self, target_module: str):
            self.target_module = target_module
            self.collecting = False
            self.seen_target = False
            self.ports: List[Port] = []

        def __call__(self, obj):
            try:
                from pyslang.ast import PackedArrayType, ScalarType
            except ImportError:
                return

            kind = type(obj).__name__

            if kind == "InstanceSymbol":
                instance_name = getattr(obj, "name", None)
                if not self.seen_target and instance_name == self.target_module:
                    self.collecting = True
                    self.seen_target = True
                elif self.seen_target and self.collecting:
                    self.collecting = False
                return

            if kind != "PortSymbol" or not self.collecting:
                return

            internal_sym = obj.internalSymbol
            if not internal_sym:
                return

            var_type = internal_sym.type
            data_type, width, dimensions = "logic", 1, ""

            if isinstance(var_type, ScalarType):
                data_type = str(var_type.scalarKind).split(".")[-1].lower()
            elif isinstance(var_type, PackedArrayType):
                width = var_type.bitWidth
                array_range = var_type.range
                dimensions = f"[{array_range.left}:{array_range.right}]"

                elem_type = var_type
                while isinstance(elem_type, PackedArrayType):
                    elem_type = elem_type.elementType
                if isinstance(elem_type, ScalarType):
                    data_type = str(elem_type.scalarKind).split(".")[-1].lower()

            direction = str(obj.direction).split(".")[-1].lower()
            direction = "input" if direction == "in" else "output" if direction == "out" else direction

            self.ports.append(Port(
                name=obj.name,
                direction=direction,
                data_type=data_type,
                width=width,
                dimensions=dimensions
            ))

    def extract(self, rtl_path: Path, filelist_path: Optional[Path] = None) -> List[Port]:
        try:
            from pyslang import DiagnosticEngine, SourceManager, TextDiagnosticClient
            from pyslang.syntax import SyntaxTree
            from pyslang.ast import Compilation
        except ImportError:
            Logger.error("pyslang is required. Install it with: pip install pyslang")
            sys.exit(1)

        syntax_trees = []
        source_manager = SourceManager()

        if filelist_path:
            resolver = FilelistResolver(Path(rtl_path.anchor))
            source_files, include_dirs = resolver.collect_sources(filelist_path)
            
            for inc in include_dirs:
                try:
                    source_manager.addUserDirectories(str(inc))
                except TypeError:
                    source_manager.addUserDirectories([str(inc)])

            source_set = {str(p.resolve()) for p in source_files}
            source_set.add(str(rtl_path.resolve()))

            for sf in sorted(source_set):
                if Path(sf).is_file():
                    syntax_trees.append(SyntaxTree.fromFile(sf, source_manager))

        if not syntax_trees:
            syntax_trees.append(SyntaxTree.fromFile(str(rtl_path.resolve()), source_manager))

        compilation = Compilation()
        for tree in syntax_trees:
            compilation.addSyntaxTree(tree)

        diagnostics = compilation.getAllDiagnostics()
        diag_client = TextDiagnosticClient()
        diag_engine = DiagnosticEngine(compilation.sourceManager)
        diag_engine.addClient(diag_client)

        for diag in diagnostics:
            diag_engine.issue(diag)

        if diag_output := diag_client.getString():
            Logger.step("Compiler Diagnostics")
            print(diag_output)

        visitor = self._PortVisitor(self.target_module)
        compilation.getRoot().visit(visitor)

        if not visitor.ports:
            raise Exception("AST Elaboration did not produce any DUT ports.")

        return visitor.ports


# ═════════════════════════════════════════════════════════════════════════
# STRING REPLACEMENT
# ═════════════════════════════════════════════════════════════════════════

class ReplacementEngine:
    def __init__(self, target: str):
        t_lower, t_title, t_upper = target.lower(), target.capitalize(), target.upper()
        entries = [
            ("dut_", f"{t_lower}_"), ("Dut_", f"{t_title}_"), ("DUT_", f"{t_upper}_"),
            ("dut", t_lower), ("Dut", t_title), ("DUT", t_upper),
        ]
        
        self.subs = []
        for old, new in entries:
            pat = re.compile(re.escape(old)) if old.endswith("_") else re.compile(rf"\b{re.escape(old)}\b")
            self.subs.append((new, pat))

    def rename(self, text: str) -> str:
        for new, pattern in self.subs:
            text = pattern.sub(new, text)
        return text

    def rename_path(self, path: Path) -> Path:
        return Path(self.rename(str(path)))


# ═════════════════════════════════════════════════════════════════════════
# TEMPLATE ENGINE
# ═════════════════════════════════════════════════════════════════════════

class TemplateEngine:
    SENTINELS = {
        "INPUT":  ["i_din", "I_DIN", "Din", "din"],
        "OUTPUT": ["o_dout", "O_DOUT", "Dout", "dout"],
    }
    
    BLOCK_RE = re.compile(
        r"[ \t]*// GEN:BEGIN[ \t]+(\w+)(?:[ \t]+(LIST))?[ \t]*\r?\n"
        r"(.*?)\r?\n"
        r"[ \t]*// GEN:END[ \t]*\r?\n?",
        re.DOTALL,
    )
    
    REMOVE_RE = re.compile(
        r"[ \t]*// GEN:REMOVE:BEGIN[ \t]*\r?\n"
        r".*?\r?\n"
        r"[ \t]*// GEN:REMOVE:END[ \t]*\r?\n?",
        re.DOTALL,
    )

    def __init__(self):
        self.warnings: List[str] = []
        self.current_file_label = ""

    def _sentinel_pattern(self, sentinel: str) -> re.Pattern:
        return re.compile(rf"(?<![A-Za-z0-9]){re.escape(sentinel)}(?![A-Za-z0-9])")

    def _render_port(self, template_body: str, tag: str, port: Port) -> str:
        text = template_body
        for sentinel in self.SENTINELS.get(tag, []):
            text = self._sentinel_pattern(sentinel).sub(port.name, text)
        text = re.sub(r"\[\d+:0\]", port.range, text)
        text = re.sub(r"\[16\]", f"[{max(port.width, 1)}]", text)
        return text

    def _strip_removed(self, text: str) -> str:
        return self.REMOVE_RE.sub("", text)

    def _cleanup_lists(self, text: str) -> str:
        text = re.sub(r",(\s*\n(?:[ \t]*//[^\n]*\n)*[ \t]*\))", r"\1", text)
        return re.sub(r"\n{3,}", "\n\n", text)

    def render(self, text: str, ports: List[Port], file_label: str) -> str:
        self.current_file_label = file_label
        text = self._strip_removed(text)

        def replacer(m):
            tag = m.group(1).upper()
            is_list = bool(m.group(2))
            body = m.group(3).strip("\n")

            has_sentinel = any(self._sentinel_pattern(s).search(body) for s in self.SENTINELS.get(tag, []))
            if tag in self.SENTINELS and not has_sentinel:
                self.warnings.append(
                    f"{file_label}: block tagged '{tag}' lacks a sentinel. Content: {body.strip()[:80]!r}"
                )

            matching = [p for p in ports if p.direction == tag.lower()]
            if not matching:
                return ""

            if is_list:
                lines = body.split("\n")
                if lines[-1].rstrip().endswith(","):
                    lines[-1] = lines[-1].rstrip()[:-1]
                base = "\n".join(lines)
                rendered = [self._render_port(base, tag, p) + "," for p in matching]
            else:
                rendered = [self._render_port(body, tag, p) for p in matching]

            return "\n".join(rendered) + "\n"

        text = self.BLOCK_RE.sub(replacer, text)
        text = self._cleanup_lists(text)

        if any(marker in text for marker in ("GEN:BEGIN", "GEN:END", "GEN:REMOVE")):
            self.warnings.append(f"{file_label}: unresolved GEN marker(s) left in output.")

        return text


# ═════════════════════════════════════════════════════════════════════════
# FILESYSTEM BUILDER
# ═════════════════════════════════════════════════════════════════════════

class EnvironmentBuilder:
    def __init__(self, template_engine: TemplateEngine, replacement_engine: ReplacementEngine, config: GeneratorConfig):
        self.template = template_engine
        self.replacer = replacement_engine
        self.config = config

    def _is_text_file(self, path: Path) -> bool:
        try:
            with path.open("r", encoding="utf-8") as f:
                f.read(512)
            return True
        except (UnicodeDecodeError, OSError):
            return False

    def generate(self, ports: List[Port]) -> List[str]:
        Logger.info(f"Source  : {self.config.template_dir}")
        Logger.info(f"Output  : {self.config.output_dir}\n")

        if self.config.output_dir.exists():
            if self.config.overwrite:
                Logger.warn(f"Output directory exists - removing: {self.config.output_dir}")
                shutil.rmtree(self.config.output_dir)
            else:
                Logger.error(f"Output directory exists: {self.config.output_dir}. Use --overwrite.")
                sys.exit(1)

        for src_path in self.config.template_dir.rglob("*"):
            if src_path.is_dir() or any(d.startswith(".") for d in src_path.parts):
                continue

            rel_src = src_path.relative_to(self.config.template_dir)
            if any(fnmatch.fnmatch(src_path.name, pat) for pat in self.config.exclude):
                print(f"  [skipped         ]  {rel_src}")
                continue

            rel_dst = self.replacer.rename_path(rel_src)
            dst_path = self.config.output_dir / rel_dst
            dst_path.parent.mkdir(parents=True, exist_ok=True)

            if self._is_text_file(src_path):
                content = src_path.read_text(encoding="utf-8")
                content = self.replacer.rename(content)
                content = self.template.render(content, ports, str(rel_src))
                dst_path.write_text(content, encoding="utf-8", newline="\n")
                status = "generated"
            else:
                shutil.copy2(src_path, dst_path)
                status = "copied (binary)"

            print(f"  [{status:<16}]  {rel_src}  ->  {rel_dst}")

        return self.template.warnings


# ═════════════════════════════════════════════════════════════════════════
# GENERATOR FACADE
# ═════════════════════════════════════════════════════════════════════════

class UVMEnvGenerator:
    def __init__(self, config: GeneratorConfig):
        self.config = config
        self.resolver = FilelistResolver(config.repo_root)

    def extract_ports(self) -> Tuple[Path, List[Port]]:
        rtl_path = self.resolver.resolve_dut(self.config.dut_ref)
        dut_name = rtl_path.stem
        sim_dir, compile_f, design_f = self.resolver.find_sim_filelists(rtl_path)

        Logger.step("Stage 1: Extracting ports from RTL")
        Logger.info(f"DUT file     : {rtl_path}")
        Logger.info(f"sim/ dir     : {sim_dir}")
        Logger.info(f"compile.f    : {compile_f}")
        Logger.info(f"design.f     : {design_f}\n")

        extractor = RTLPortExtractor(dut_name)
        ports = extractor.extract(rtl_path, compile_f)

        if not ports:
            Logger.error("No ports extracted - check the RTL file / module syntax.")
            sys.exit(1)

        print(json.dumps([asdict(p) for p in ports], indent=2))
        
        if self.config.dump_ports:
            with self.config.dump_ports.open("w", encoding="utf-8") as f:
                json.dump([asdict(p) for p in ports], f, indent=2)
            Logger.info(f"Port list written to {self.config.dump_ports}")
        print()
        
        return rtl_path, ports

    def build(self, ports: List[Port]):
        Logger.step("Stage 2+3: Generating environment")
        Logger.info(f"Target        : {self.config.target}")
        Logger.info(f"Ports found   : {len(ports)} "
                    f"({sum(1 for p in ports if p.direction=='input')} input, "
                    f"{sum(1 for p in ports if p.direction=='output')} output)\n")

        template_engine = TemplateEngine()
        replacer = ReplacementEngine(self.config.target)
        builder = EnvironmentBuilder(template_engine, replacer, self.config)
        
        warnings = builder.generate(ports)

        print()
        Logger.success(f"UVM environment generated at: {self.config.output_dir.resolve()}")

        if warnings:
            print()
            Logger.step(f"{len(warnings)} marker warning(s) - review before compiling")
            for w in warnings:
                Logger.warn(w)
            sys.exit(1)

    def run(self):
        _, ports = self.extract_ports()
        self.build(ports)


# ═════════════════════════════════════════════════════════════════════════
# PATH RESOLUTION HELPER (NEW!)
# ═════════════════════════════════════════════════════════════════════════

def resolve_default_output_dir(target: str, project_root: Path) -> Path:
    """
    Smart routing based on the target/folder suffix:
    - Ends with '_subsystem' -> project_root / 'subsystem' / <target>
    - Ends with '_system'    -> project_root / 'system' / <target>
    - Otherwise              -> project_root / 'ip' / <target>
    
    Note: We check '_subsystem' first because '_subsystem' also ends with '_system'!
    """
    target_lower = target.lower()
    if target_lower.endswith("_subsystem"):
        base_dir = project_root / "subsystem"
    elif target_lower.endswith("_system"):
        base_dir = project_root / "system"
    else:
        base_dir = project_root / "ip"
        
    return base_dir / target


# ═════════════════════════════════════════════════════════════════════════
# CLI ENTRY POINT
# ═════════════════════════════════════════════════════════════════════════

def main() -> None:
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    repo_root = project_root.parent
    default_template = script_dir / "src"
    
    DEFAULT_SKIP = {"generate_uvm_env.py", "dut.sv"}

    parser = argparse.ArgumentParser(description="One-shot UVM environment generator.")
    parser.add_argument("dut_ref", help="DUT name or RTL path to parse")
    parser.add_argument("target", nargs="?", default=None, help="Target replacement name")
    parser.add_argument("--template", default=str(default_template), help=f"Template dir (default: {default_template})")
    parser.add_argument("--output", default=None, help="Destination dir (defaults to ip/, subsystem/, or system/ based on target suffix)")
    parser.add_argument("--exclude", nargs="+", metavar="PATTERN", default=[], help=f"Extra skips. Built-ins: {sorted(DEFAULT_SKIP)}")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing output directory")
    parser.add_argument("--dump-ports", type=Path, default=None, help="Dump ports to JSON file")

    args = parser.parse_args()

    resolver = FilelistResolver(repo_root)
    rtl_path = resolver.resolve_dut(args.dut_ref)
    dut_name = rtl_path.stem
    target = (args.target or dut_name).strip().lower()

    if not re.fullmatch(r"[a-z][a-z0-9_]*", target):
        Logger.error("Target name must start with a letter and contain only lowercase letters, digits, and underscores.")
        sys.exit(1)

    template_dir = Path(args.template).resolve()
    if not template_dir.is_dir():
        Logger.error(f"Template directory not found: {template_dir}")
        sys.exit(1)

    # Use explicit output if provided, otherwise route based on suffix logic
    if args.output:
        output_dir = Path(args.output).resolve()
    else:
        output_dir = resolve_default_output_dir(target, project_root)

    config = GeneratorConfig(
        dut_ref=args.dut_ref,
        target=target,
        template_dir=template_dir,
        output_dir=output_dir,
        exclude=DEFAULT_SKIP | set(args.exclude),
        overwrite=args.overwrite,
        dump_ports=args.dump_ports,
        repo_root=repo_root
    )

    generator = UVMEnvGenerator(config)
    generator.run()


if __name__ == "__main__":
    main()