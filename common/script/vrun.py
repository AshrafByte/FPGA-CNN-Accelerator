#!/usr/bin/env python3
"""
common/script/vrun.py - Verification regression runner

=================================================================================
ASSUMPTIONS - if any of these don't hold, this script either won't work at all,
or will run but do something other than what you expect. Read this before
debugging anything unexpected.
=================================================================================

MODULE DISCOVERY
  - Every module (hw/ or verif/) has a sim/compile.f - that's the ONLY signal
    used to discover modules at all (find_all_modules() greps for this exact
    path shape). A module without sim/compile.f is invisible to this tool.
  - hw/ testbenches are named "<module>_tb.sv" (or, failing that, the first
    "*_tb.sv" match anywhere under the module). verif/ testbenches are
    "<module>_uvm_tb.sv". If your file doesn't match this, --top must be
    passed explicitly - auto-detection will silently pick the wrong file or
    find nothing.
  - Default UVM test name is "<module>_test" - only a NAMING CONVENTION, not
    verified against any real class. If no such test exists, Questa/DSim will
    fail at elaboration/runtime with their own "test not found" error.

FILELIST / PATH RESOLUTION
  - compile.f and any nested -f/-F filelists it references use paths resolved
    relative to the CURRENT WORKING DIRECTORY, not relative to the file that
    references them. This is WHY every compile/sim command below explicitly
    runs with cwd=module.sim_dir - nested filelists must be reachable from
    there, as plain relative paths, or the simulator will report a file
    genuinely not found even though it exists elsewhere in the repo.

QUESTA-SPECIFIC
  - run.do is the SOURCE OF TRUTH for simulation options (TOP/TEST/SEED/
    VERBOSITY/VSIM_ARGS/RECORD) - vrun.py only OVERRIDES these via injected
    `set VAR value` Tcl, and only when a flag was actually given. run.do's
    own `if {![info exists VAR]}` defaults apply otherwise - meaning run.do
    also works fine if you run `vsim -do run.do` by hand, outside vrun.py.
  - TOP is always passed as a BARE unit name (e.g. "rx_decoder_uvm_tb", never
    "work.rx_decoder_uvm_tb") - run.do itself prepends "work." exactly once.
    If you ever change the compiled library name away from "work", this
    breaks and needs updating in both places.
  - Signal discovery for the "no wave.do" fallback (both here and in
    run.do) addresses signals as "/$TOP/*" - a bare top-level instance path,
    NOT via `find instances /*`. The latter was tried and reverted: on some
    Questa versions/configs it can return internal or package-level entries
    (e.g. "#vsim_capacity#", "uvm_pkg") ahead of the real design top, and
    picking list position 0 blindly picked the wrong one. Since TOP is
    already known exactly (it's what vsim was launched with), addressing
    directly by name has no such ambiguity.
  - Only ONE real Questa/ModelSim install is trusted, even if multiple vsim
    binaries exist on PATH - verified by actually running `vsim -version`
    and checking for "Questa" in the banner, NOT by PATH order. This matters
    because OEM-limited editions (e.g. ModelSim-Altera/Intel FPGA Edition,
    bundled with Quartus) commonly coexist on the same PATH on an FPGA-dev
    machine and are NOT interchangeable with a real Questa install.
  - The bundled UVM library location is GUESSED as "<install root>/uvm-<ver>"
    (i.e. a sibling of the vsim binary's own folder). If your install layout
    differs, set QUESTA_UVM_HOME explicitly or compile will fail to find UVM.

DSIM-SPECIFIC
  - DSim has NO run.do equivalent - it's pure command-line, so vrun.py owns
    TOP/TEST/VERBOSITY/SEED outright for that backend (unlike Questa, where
    run.do owns them). --top is REQUIRED for DSim if auto-detection fails,
    since there's no fallback default the way run.do provides for Questa.
  - The DSim license file location is guessed as the standard Free Individual
    License path under %USERPROFILE%/AppData/Local/metrics-ca/ - override via
    DSIM_LICENSE if you use a different license type/location.

RECORD
  - RECORD defaults to ON (signals are recorded every run) specifically so
    that a failed `make verify` never has to be RE-RUN just to get waveform
    data - `make wave` afterward just opens what was already captured. This
    has a real simulation-speed cost; pass RECORD=0 for runs where you know
    you won't need to look (e.g. a large regress-all sweep).
  - `make wave` always opens Questa in GUI mode (never batch) - viewing a
    waveform is inherently an interactive activity, so this doesn't depend
    on or get controlled by the separate GUI= flag (which only affects the
    simulation run itself, not the wave viewer).
  - `wave.do` is OPTIONAL, both for `make verify`/`make sim` (run.do) and for
    a later `make wave` (this file): if present it's used to pre-configure
    the signal list/layout; if absent, all signals under /$TOP are recorded
    (and, in `make wave`'s case, added to the Wave pane) automatically.
"""
from __future__ import annotations

import abc
import argparse
import dataclasses
import glob
import io
import os
import pathlib
import shutil
import subprocess
import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent   # common/script/vrun.py -> repo

# Windows terminals sometimes report a non-UTF-8 stdout/stderr encoding,
# which garbles any non-ASCII characters (box-drawing chars from a custom
# UVM report server, etc.). Force UTF-8 so the same output renders correctly
# regardless of the terminal's default codepage.
if sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
if sys.stderr.encoding != 'utf-8':
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')


def run_command(cmd: str, cwd: Path, env: dict[str, str] | None = None) -> None:
    """Run a shell command cross-platform: cmd.exe on Windows, bash on POSIX
    (POSIX default /bin/sh - e.g. dash on Debian/Ubuntu - doesn't support
    `source`, which DSim's activation needs, so bash is explicit here)."""
    print(f"    ({cwd})$ {cmd}")
    full_env = {**os.environ, **(env or {})}
    if os.name == "nt":
        result = subprocess.run(cmd, cwd=cwd, shell=True, env=full_env)
    else:
        result = subprocess.run(["bash", "-c", cmd], cwd=cwd, env=full_env)
    if result.returncode != 0:
        sys.exit(result.returncode)


# --- Data Models ---

@dataclass(frozen=True)
class Module:
    path: Path
    kind: str

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def absolute_path(self) -> Path:
        return REPO_ROOT / self.path

    @property
    def sim_dir(self) -> Path:
        return self.absolute_path / "sim"


@dataclass
class RunConfig:
    simulator: str | None
    top: str | None
    test: str | None
    seed: str
    verbosity: str
    verbosity_map: str | None
    gui: bool
    uvm_ver: str
    pattern: str | None = None
    compile_args: str | None = None
    sim_args: str | None = None
    coverage: bool = False  # Note: Impacts compile/sim performance; opt-in only
    record: bool = True      # Recording ON by default so a failed run never needs
                             # re-running just to get waveform data for `make wave`.

    def build_verbosity_plusargs(self) -> str:
        if not self.verbosity_map:
            return ""
        pairs = []
        for entry in self.verbosity_map.split(","):
            entry = entry.strip()
            if not entry:
                continue
            if "=" not in entry:
                sys.exit(f"ERROR: malformed --verbosity-map entry '{entry}' - expected name=LEVEL")
            name, level = entry.split("=", 1)
            pairs.append((name.strip().upper(), level.strip().upper()))
        return " ".join(f"+{name}_VERBOSITY={level}" for name, level in pairs)


# --- Module Discovery & Resolution ---

class ModuleRegistry:
    def __init__(self, repo_root: Path = REPO_ROOT):
        self.repo_root = repo_root

    def find_all_modules(self) -> dict[str, list[Module]]:
        result: dict[str, list[Module]] = {"hw": [], "verif": []}
        for kind in ("hw", "verif"):
            tree_dir = self.repo_root / kind
            if not tree_dir.is_dir():
                continue
            for compile_f in tree_dir.rglob("sim/compile.f"):
                rel_path = compile_f.parent.parent.relative_to(self.repo_root)
                result[kind].append(Module(path=rel_path, kind=kind))
        for kind in result:
            result[kind] = sorted(result[kind], key=lambda m: m.name)
        return result

    def resolve_module(self, name: str, candidates: list[Module]) -> Module:
        if "/" in name or "\\" in name:
            p = Path(name)
            for cand in candidates:
                if cand.path == p:
                    return cand
            sys.exit(f"ERROR: '{name}' is not a known module path. Run 'vrun.py list'.")
        matches = [m for m in candidates if m.name == name]
        if not matches:
            sys.exit(f"ERROR: no module named '{name}' found. Run 'vrun.py list' to see options.")
        if len(matches) > 1:
            listing = "\n  ".join(str(m.path) for m in matches)
            sys.exit(f"ERROR: '{name}' is ambiguous:\n  {listing}\nPass a full path instead.")
        return matches[0]

    def resolve_any_scope(self, spec: str) -> Module:
        modules = self.find_all_modules()
        all_modules = modules["hw"] + modules["verif"]
        if "/" in spec or "\\" in spec:
            p = Path(spec)
            for m in all_modules:
                if m.path == p:
                    return m
            tree, _, short = spec.replace("\\", "/").partition("/")
            if tree in modules and short:
                matches = [m for m in modules[tree] if m.name == short]
                if not matches:
                    sys.exit(f"ERROR: no module named '{short}' found under {tree}/. Run 'vrun.py list'.")
                if len(matches) > 1:
                    listing = "\n  ".join(str(m.path) for m in matches)
                    sys.exit(f"ERROR: '{short}' is ambiguous under {tree}/:\n  {listing}")
                return matches[0]
            sys.exit(f"ERROR: '{spec}' is not a known module path. Run 'vrun.py list'.")
        matches = [m for m in all_modules if m.name == spec]
        if not matches:
            sys.exit(f"ERROR: no module named '{spec}' found. Run 'vrun.py list' to see options.")
        if len(matches) > 1:
            listing = "\n  ".join(str(m.path) for m in matches)
            sys.exit(f"ERROR: '{spec}' is ambiguous:\n  {listing}\nDisambiguate with IP=hw/{spec} or IP=verif/{spec}.")
        return matches[0]

    @staticmethod
    def auto_detect_top(module: Module, suffix: str) -> str | None:
        exact_name = f"{module.name}_{suffix}"
        exact_matches = sorted(module.absolute_path.rglob(exact_name))
        if exact_matches:
            return exact_matches[0].stem
        any_matches = sorted(module.absolute_path.rglob(f"*_{suffix}"))
        if any_matches:
            return any_matches[0].stem
        return None

    @staticmethod
    def auto_detect_test(module: Module) -> str:
        return f"{module.name}_test"


# --- Environment Configurations ---

class DSimEnvironment:
    @property
    def library_name(self) -> str:
        return os.environ.get("DSIM_LIB", "work")

    @property
    def license_path(self) -> str:
        default_path = (
            Path(os.environ.get("USERPROFILE", os.environ.get("HOME", "")))
            / "AppData" / "Local" / "metrics-ca" / "dsim-license.json"
        )
        return os.environ.get("DSIM_LICENSE", str(default_path))

    def resolve_install_path(self) -> Path | None:
        override = os.environ.get("DSIM_INSTALL")
        if override:
            return Path(override)
        if os.name == "nt":
            pattern = "C:/Program Files/Altair/DSim/*"
            activate_name = "shell_activate.bat"
        else:
            pattern = str(Path.home() / "AltairDSim" / "*")
            activate_name = "shell_activate.bash"
        candidates = [Path(p) for p in glob.glob(pattern)
                      if Path(p).is_dir() and (Path(p) / activate_name).is_file()]
        return sorted(candidates, key=lambda p: p.name)[-1] if candidates else None

    def get_activation_snippet(self) -> str:
        install = self.resolve_install_path()
        if not install:
            sys.exit("ERROR: Could not locate DSim installation path dynamically. Please set DSIM_INSTALL environment variable.")
        ext = "bat" if os.name == "nt" else "bash"
        cmd_prefix = "call" if os.name == "nt" else "source"
        activate_file = install / f"shell_activate.{ext}"
        if not activate_file.is_file():
            sys.exit(f"ERROR: Activation script path variant not found at: {activate_file}")
        return f'{cmd_prefix} "{activate_file}"'

    def get_license_env(self) -> dict[str, str]:
        lic = self.license_path
        if not Path(lic).is_file():
            sys.exit(f"ERROR: DSim license file not found at {lic}\nDownload it from DSim Studio or explicitly configure DSIM_LICENSE.")
        return {"DSIM_LICENSE": lic}


class QuestaEnvironment:
    def __init__(self):
        self._install_path: Path | None = None
        self._resolved = False

    def resolve_install_path(self) -> Path | None:
        if self._resolved:
            return self._install_path
        self._resolved = True
        override = os.environ.get("QUESTA_INSTALL")
        if override:
            self._install_path = Path(override)
            return self._install_path
        path_dirs = os.environ.get("PATH", "").split(os.pathsep)
        vsim_name = "vsim.exe" if os.name == "nt" else "vsim"
        for path_str in path_dirs:
            if not path_str.strip():
                continue
            vsim_path = Path(path_str) / vsim_name
            if vsim_path.is_file():
                try:
                    result = subprocess.run(
                        [str(vsim_path), "-version"], capture_output=True, text=True, check=False
                    )
                    output = result.stdout + result.stderr
                    if "Questa" in output or "questa" in output:
                        self._install_path = vsim_path.parent
                        return self._install_path
                except Exception:
                    pass
        return None


# --- Simulator Backends ---

class SimulatorBackend(ABC):
    @abstractmethod
    def compile(self, module: Module, config: RunConfig) -> None: pass
    @abstractmethod
    def sim(self, module: Module, config: RunConfig) -> None: pass
    @abstractmethod
    def wave(self, module: Module, config: RunConfig) -> None: pass


class QuestaBackend(SimulatorBackend):
    def __init__(self, env: QuestaEnvironment):
        self.env = env

    def _get_bin(self, tool: str) -> str:
        bin_dir = self.env.resolve_install_path()
        if not bin_dir:
            sys.exit("ERROR: Questa installation not found on PATH (and QUESTA_INSTALL not set).")
        exe_name = f"{tool}.exe" if os.name == "nt" else tool
        bin_path = bin_dir / exe_name
        return f'"{bin_path}"'

    def _get_uvm_path(self, uvm_ver: str) -> str:
        """
        Resolves the UVM library path based on the requested version.
        Defaults to searching relative to the Questa installation root.
        Can be explicitly overridden via QUESTA_UVM_HOME.
        """
        override = os.environ.get("QUESTA_UVM_HOME")
        if override:
            return f'"{Path(override).as_posix()}"'
        bin_dir = self.env.resolve_install_path()
        if not bin_dir:
            sys.exit("ERROR: Questa installation not found.")
        uvm_path = bin_dir.parent / f"uvm-{uvm_ver}"
        return f'"{uvm_path.as_posix()}"'

    def compile(self, module: Module, config: RunConfig) -> None:
        compile_f = module.sim_dir / "compile.f"
        if not compile_f.is_file():
            sys.exit(f"ERROR: {compile_f} not found.")
        print(f"==> [Questa] Compiling {module.path}")
        shutil.rmtree(module.sim_dir / "work", ignore_errors=True)

        vlib = self._get_bin("vlib")
        vlog = self._get_bin("vlog")
        vmap = self._get_bin("vmap")
        vdir = self._get_bin("vdir")

        run_command(f"{vlib} work", cwd=module.sim_dir)

        uvm_dir = self._get_uvm_path(config.uvm_ver)
        run_command(f"{vmap} uvm12 {uvm_dir}", cwd=module.sim_dir)
        run_command(f"{vdir} -lib uvm12", cwd=module.sim_dir)
        run_command(f"{vmap} mtiUvm {uvm_dir}", cwd=module.sim_dir)

        # Apply optional coverage flags
        cover_flags = "+cover -covercells " if config.coverage else ""
        extra = f" {config.compile_args}" if config.compile_args else ""
        run_command(
            f"{vlog} -work work {cover_flags}-f compile.f{extra}",
            cwd=module.sim_dir,
        )

    def sim(self, module: Module, config: RunConfig) -> None:
        self.compile(module, config)
        run_do = module.sim_dir / "run.do"
        if not run_do.is_file():
            sys.exit(f"ERROR: {run_do} not found.")
        print(f"==> [Questa] Simulating {module.path} TEST={config.test} SEED={config.seed}")

        vsim = self._get_bin("vsim")
        tcl = []

        # Pass the bare top module name to Tcl; run.do prepends the library prefix.
        if config.top:
            tcl.append(f"set TOP {config.top}")
        if config.test:
            tcl.append(f"set TEST {config.test}")
        if config.seed is not None:
            tcl.append(f"set SEED {config.seed}")
        if config.verbosity:
            tcl.append(f"set VERBOSITY {config.verbosity}")
        if config.sim_args:
            tcl.append(f"set VSIM_ARGS {{{config.sim_args}}}")
        tcl.append(f"set RECORD {1 if config.record else 0}")

        plusargs = config.build_verbosity_plusargs()
        if plusargs:
            print(f"    per-UVC verbosity overrides: {plusargs}")
            tcl.append(f"set EXTRA_PLUSARGS {{{plusargs}}}")

        tcl.append("do run.do")
        gui_flag = "" if config.gui else "-c"
        cmd = f'{vsim} {gui_flag} -do "{"; ".join(tcl)}"'
        run_command(cmd, cwd=module.sim_dir)

    def wave(self, module: Module, config: RunConfig) -> None:
        """Always opens interactively (no -c) - viewing waves is inherently
        a GUI activity, independent of the separate GUI= flag (which only
        controls the simulation run itself). wave.do is OPTIONAL: if present
        it's used to pre-configure the signal list/layout; if absent, every
        signal run.do already recorded under /$TOP is added automatically,
        so a plain batch `make verify` never blocks a later `make wave`."""
        if not (module.sim_dir / "vsim.wlf").is_file():
            sys.exit(
                f"ERROR: no vsim.wlf found for {module.path}. Run "
                f"'make sim/verify IP=...' first (RECORD=1 is the default, "
                f"so a normal run should already have produced one unless "
                f"you explicitly passed RECORD=0)."
            )
        vsim = self._get_bin("vsim")
        if (module.sim_dir / "wave.do").is_file():
            do_cmd = "do wave.do"
        elif config.top:
            # Same /$TOP/* addressing run.do already uses live - a saved
            # .wlf retains the original hierarchy, and vsim -view sets that
            # dataset as the active context, so the same plain path works.
            print(f"INFO: wave.do not found. Adding all signals under /{config.top}.")
            do_cmd = f"view wave; add wave -r /{config.top}/*"
        else:
            # Shouldn't normally happen - execute_wave() auto-detects TOP
            # the same way verify/sim do - but fall back to a bare, still-
            # usable viewer rather than erroring outright if it ever does.
            print("WARNING: wave.do not found and TOP could not be determined - opening with an empty Wave pane.")
            do_cmd = "view wave"
        run_command(f'{vsim} -view vsim.wlf -do "{do_cmd}"', cwd=module.sim_dir)


class DSimBackend(SimulatorBackend):
    def __init__(self, env: DSimEnvironment):
        self.env = env

    def compile(self, module: Module, config: RunConfig) -> None:
        if not (module.sim_dir / "compile.f").is_file():
            sys.exit(f"ERROR: {module.sim_dir}/compile.f not found.")
        lib = self.env.library_name
        print(f"==> [DSim] Compiling {module.path} into library '{lib}'")
        activate = self.env.get_activation_snippet()
        env_vars = self.env.get_license_env()
        run_command(f"{activate} && dvlcom -lib {lib} -uvm {config.uvm_ver} -F compile.f",
                    cwd=module.sim_dir, env=env_vars)

    def sim(self, module: Module, config: RunConfig) -> None:
        self.compile(module, config)
        if not config.top:
            sys.exit("ERROR: TOP could not be auto-detected and none was given.\nPass it explicitly, e.g. --top rx_decoder_uvm_tb")
        lib = self.env.library_name
        print(f"==> [DSim] Simulating {module.path}  TOP={config.top}  TEST={config.test}  SEED={config.seed}")
        activate = self.env.get_activation_snippet()
        env_vars = self.env.get_license_env()
        plusargs = f"+UVM_TESTNAME={config.test} " if config.test else ""
        v_overrides = config.build_verbosity_plusargs()
        if v_overrides:
            print(f"    per-UVC verbosity overrides: {v_overrides}")
        run_command(
            f"{activate} && dsim -top {lib}.{config.top} -L {lib} "
            f"-uvm {config.uvm_ver} -waves waves.vcd +UVM_NO_RELNOTES {plusargs}"
            f"+UVM_VERBOSITY={config.verbosity} -sv_seed {config.seed} {v_overrides}",
            cwd=module.sim_dir, env=env_vars,
        )

    def wave(self, module: Module, config: RunConfig) -> None:
        if not (module.sim_dir / "waves.vcd").is_file():
            sys.exit("ERROR: no waves.vcd found - run 'sim'/'verify' with --simulator dsim first.")
        activate = self.env.get_activation_snippet()
        env_vars = self.env.get_license_env()
        run_command(f"{activate} && dsim -waves waves.vcd -view", cwd=module.sim_dir, env=env_vars)


# --- Runner & Factory Integration ---

class BackendFactory:
    def __init__(self, questa_env: QuestaEnvironment, dsim_env: DSimEnvironment):
        self.questa_env = questa_env
        self.dsim_env = dsim_env

    def detect_available(self) -> list[str]:
        found = []
        if self.questa_env.resolve_install_path() is not None:
            found.append("questa")
        if self.dsim_env.resolve_install_path() is not None:
            found.append("dsim")
        return found

    def create(self, config: RunConfig) -> SimulatorBackend:
        if not config.simulator:
            found = self.detect_available()
            if not found:
                sys.exit("ERROR: No simulator detected (Questa/DSim installs not found). Pass --simulator explicitly.")
            if len(found) > 1:
                sys.exit(f"ERROR: Multiple simulators detected ({', '.join(found)}). Pass --simulator to choose one.")
            config.simulator = found[0]
            print(f"==> Auto-detected simulator: {config.simulator}")
        if config.simulator == "questa":
            return QuestaBackend(self.questa_env)
        elif config.simulator == "dsim":
            return DSimBackend(self.dsim_env)
        sys.exit(f"ERROR: Unsupported simulator backend option: {config.simulator}")


class VerificationRunner:
    QUESTA_CLEAN = ["work", "transcript", "vsim.wlf"]
    QUESTA_GLOBS = ["*.wlf", "*cr.mti", "vlft??????"]
    DSIM_CLEAN   = ["dsim_work", "dsim.env", "dsim.log", "dvlcom.env", "dvlcom.log", "metrics.db", "tr_db.log"]
    DSIM_GLOBS   = ["*.vcd"]

    def __init__(self, registry: ModuleRegistry, backend_factory: BackendFactory):
        self.registry = registry
        self.backend_factory = backend_factory

    def _clear_artifacts(self, sim_dir: Path) -> None:
        for name in self.QUESTA_CLEAN + self.DSIM_CLEAN:
            p = sim_dir / name
            if p.is_dir():
                shutil.rmtree(p, ignore_errors=True)
            elif p.is_file():
                p.unlink(missing_ok=True)
        for pattern in self.QUESTA_GLOBS + self.DSIM_GLOBS:
            for p in sim_dir.glob(pattern):
                p.unlink(missing_ok=True)

    def list_modules(self) -> None:
        modules = self.registry.find_all_modules()
        print("hw/ modules      (use with: vrun.py sim <name>):")
        for m in modules["hw"]:
            print(f"  {m.name}  ->  {m.path}")
        print("\nverif/ modules   (use with: vrun.py verify <name>):")
        for m in modules["verif"]:
            print(f"  {m.name}  ->  {m.path}")

    def execute_sim(self, ip_spec: str, config: RunConfig) -> None:
        backend = self.backend_factory.create(config)
        modules = self.registry.find_all_modules()
        module = self.registry.resolve_module(ip_spec, modules["hw"])
        if not config.top:
            config.top = self.registry.auto_detect_top(module, "tb.sv")
        print(f"==> IP='{ip_spec}' resolved to {module.path}  (TOP={config.top})")
        backend.sim(module, config)

    def execute_verify(self, ip_spec: str, config: RunConfig) -> None:
        backend = self.backend_factory.create(config)
        modules = self.registry.find_all_modules()
        module = self.registry.resolve_module(ip_spec, modules["verif"])
        if not config.top:
            config.top = self.registry.auto_detect_top(module, "uvm_tb.sv")
        if not config.test:
            config.test = self.registry.auto_detect_test(module)
        print(f"==> IP='{ip_spec}' resolved to {module.path}  (TOP={config.top}  TEST={config.test})")
        backend.sim(module, config)

    def execute_compile(self, ip_spec: str, config: RunConfig) -> None:
        backend = self.backend_factory.create(config)
        module = self.registry.resolve_any_scope(ip_spec)
        backend.compile(module, config)

    def execute_wave(self, ip_spec: str, config: RunConfig) -> None:
        backend = self.backend_factory.create(config)
        module = self.registry.resolve_any_scope(ip_spec)
        # TOP isn't required on the command line for `make wave` (unlike
        # sim/verify it's rarely passed explicitly), but QuestaBackend.wave()
        # needs it to address /$TOP/* when wave.do is absent - auto-detect
        # it the same way verify/sim do rather than leaving it unset.
        if not config.top:
            suffix = "uvm_tb.sv" if module.kind == "verif" else "tb.sv"
            config.top = self.registry.auto_detect_top(module, suffix)
        backend.wave(module, config)

    def execute_clean(self, ip_spec: str) -> None:
        module = self.registry.resolve_any_scope(ip_spec)
        self._clear_artifacts(module.sim_dir)

    def execute_clean_all(self) -> None:
        modules = self.registry.find_all_modules()
        for m in modules["hw"] + modules["verif"]:
            print(f"Cleaning {m.path}")
            self._clear_artifacts(m.sim_dir)

    def execute_regress_all(self, config: RunConfig) -> None:
        backend = self.backend_factory.create(config)
        modules = self.registry.find_all_modules()
        all_modules = modules["hw"] + modules["verif"]
        selected = [m for m in all_modules if m.path.match(config.pattern)] if config.pattern else all_modules
        for m in selected:
            local_config = dataclasses.replace(config, top=None, test=None)
            if m.kind == "hw":
                local_config.top = self.registry.auto_detect_top(m, "tb.sv")
            else:
                local_config.top = self.registry.auto_detect_top(m, "uvm_tb.sv")
                local_config.test = self.registry.auto_detect_test(m)
            print(f"=== Regressing {m.path} (simulator={config.simulator}, TOP={local_config.top}, TEST={local_config.test}) ===")
            backend.sim(m, local_config)


def add_common_sim_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--simulator", default=os.environ.get("SIMULATOR"), choices=["questa", "dsim"])
    parser.add_argument("--top", default=None,
                        help="Top module, BARE name e.g. rx_decoder_uvm_tb (no 'work.' prefix). "
                             "Auto-detected from <ip>_uvm_tb.sv (verif/) or <ip>_tb.sv (hw/) if omitted.")
    parser.add_argument("--test", default=None, help="UVM_TESTNAME")
    parser.add_argument("--seed", default="random")
    parser.add_argument("--verbosity", default="UVM_MEDIUM")
    parser.add_argument("--verbosity-map", default=os.environ.get("VERBOSITY_MAP"), dest="verbosity_map",
                        help='Per-UVC verbosity overrides mapping name=level. Expands to plusargs.')
    parser.add_argument("--gui", action="store_true", help="Launch Questa GUI instead of batch")
    parser.add_argument("--coverage", action="store_true",
                        help="Compile with +cover -covercells (Questa). Off by default - real compile/sim perf cost.")
    parser.add_argument("--no-record", action="store_true", dest="no_record",
                        help="Skip signal recording. Recording is ON by default.")
    parser.add_argument("--uvm-ver", default="1.2", dest="uvm_ver")
    parser.add_argument("--compile-args", default=None, dest="compile_args",
                        help='Extra flags appended to the compile command')
    parser.add_argument("--sim-args", default=None, dest="sim_args",
                        help='Override run.do\'s VSIM_ARGS default, e.g. "-voptargs=+acc -cover -suppress 3070"')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("list", help="List all discovered hw/ and verif/ modules")

    p_sim = subparsers.add_parser("sim", help="Compile + run once, no TEST/UVM assumptions")
    p_sim.add_argument("ip", help="Short module name or path (e.g. rx_decoder, or hw/rx_decoder).")
    add_common_sim_arguments(p_sim)

    p_ver = subparsers.add_parser(
        "verify",
        help="Compile + run a UVM test (verif/ module; TB must be named <ip>_uvm_tb.sv)",
    )
    p_ver.add_argument("ip", help="verif/ module name (e.g. rx_decoder). TB must be <ip>_uvm_tb.sv unless --top is given.")
    add_common_sim_arguments(p_ver)

    for cmd, help_text in [
        ("compile", "Compile only, no simulation (IP=hw/<name> or IP=verif/<name>)"),
        ("wave", "Open Questa GUI on a previous run's vsim.wlf (IP=hw/<name> or IP=verif/<name>)"),
        ("clean", "Remove sim artifacts for one module (IP=hw/<name> or IP=verif/<name>)"),
    ]:
        p = subparsers.add_parser(cmd, help=help_text)
        p.add_argument("ip")
        if cmd != "clean":
            add_common_sim_arguments(p)

    subparsers.add_parser("clean-all", help="Remove sim artifacts for every discovered module")

    p_reg = subparsers.add_parser("regress-all", help="Run sim on every module matching PATTERN (default: all)")
    p_reg.add_argument("--pattern", default=None, help='Glob against module path, e.g. "verif/*"')
    add_common_sim_arguments(p_reg)
    
    args = parser.parse_args()

    registry = ModuleRegistry()
    questa_env = QuestaEnvironment()
    dsim_env = DSimEnvironment()
    factory = BackendFactory(questa_env, dsim_env)
    runner = VerificationRunner(registry, factory)

    config = RunConfig(
        simulator=getattr(args, "simulator", None),
        top=getattr(args, "top", None),
        test=getattr(args, "test", None),
        seed=getattr(args, "seed", "random"),
        verbosity=getattr(args, "verbosity", "UVM_MEDIUM"),
        verbosity_map=getattr(args, "verbosity_map", None),
        gui=getattr(args, "gui", False),
        uvm_ver=getattr(args, "uvm_ver", "1.2"),
        pattern=getattr(args, "pattern", None),
        compile_args=getattr(args, "compile_args", None),
        sim_args=getattr(args, "sim_args", None),
        coverage=getattr(args, "coverage", False),
        record=not getattr(args, "no_record", False),
    )

    match args.command:
        case "list":        runner.list_modules()
        case "sim":         runner.execute_sim(args.ip, config)
        case "verify":      runner.execute_verify(args.ip, config)
        case "compile":     runner.execute_compile(args.ip, config)
        case "wave":        runner.execute_wave(args.ip, config)
        case "clean":       runner.execute_clean(args.ip)
        case "clean-all":   runner.execute_clean_all()
        case "regress-all": runner.execute_regress_all(config)
        case _:             print(f"ERROR: Unknown command '{args.command}'")


if __name__ == "__main__":
    main()