# RTL & Verification Coding Conventions

This document defines the RTL, testbench, and verification coding standard for this project. Follow it for every file you add under `hw/`, `verif/`, `common/`, and `docs/`. If you're touching this repo for the first time, read section 2 and section 19 before you write anything.

---

## Table of Contents

1. [Scope & Goals](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#1-scope--goals)
2. [Repository Structure](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#2-repository-structure)
3. [File Naming Conventions](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#3-file-naming-conventions)
4. [Module & Instance Naming](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#4-module--instance-naming)
5. [Signal Naming Conventions](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#5-signal-naming-conventions)
6. [Parameters, Localparams & Enums](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#6-parameters-localparams--enums)
7. [Fixed-Point & Numeric Conventions](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#7-fixed-point--numeric-conventions)
8. [FSM Conventions](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#8-fsm-conventions)
9. [Standard RTL Module Template](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#9-standard-rtl-module-template)
10. [Formatting Rules](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#10-formatting-rules)
11. [UVM / Verification Environment Conventions](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#11-uvm--verification-environment-conventions)
12. [Golden-Model & Correctness Verification](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#12-golden-model--correctness-verification)
13. [FPGA Synthesis, Timing & Power Reporting](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#13-fpga-synthesis-timing--power-reporting)
14. [Comments & Documentation](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#14-comments--documentation)
15. [Forbidden Practices](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#15-forbidden-practices)
16. [Additional Recommendations](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#16-additional-recommendations)
17. [Git Commit Message Conventions](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#17-git-commit-message-conventions)
18. [Pre-Commit Checklist](https://claude.ai/chat/dea2059b-7606-4d1f-9c2e-596c16b9b49e#18-pre-commit-checklist)

---

## 1. Scope & Goals

1. **Correctness first** — every block's RTL must match its golden/reference model bit-exactly.
2. **Consistency** — anyone on the team can open any block and immediately recognize the naming/style, because it's the same everywhere.
3. **Reviewability** — code and docs should read like a deliberately-designed system. This matters directly for the competition report.
4. **Reusability** — the UVM environment is templated (`verif/_template/`), so naming needs to stay predictable enough for the generator (`generate_uvm_env.py`) to keep producing usable scaffolding.

---

## 2. Repository Structure

Designs move through four maturity levels: `experiments/` → `ip/` → `subsystem/` → `system/`. `verif/` mirrors `hw/` block-for-block — `hw/ip/mac_array/` always pairs with `verif/ip/mac_array/`.

```
hw/                        verif/
├── experiments/            (no formal verif/ counterpart)
├── ip/                     ├── ip/
├── subsystem/              ├── subsystem/
└── system/                 ├── system/
                            ├── common/     (shared UVCs: clk_uvc, rst_uvc, base classes)
                            └── _template/   (UVM env generator — don't hand-edit output)
```

**Every block, at every level, follows the same shape**: a `src/` folder holding the actual code, and a `sim/` folder holding the run scripts and filelists. Inside `src/`, hardware blocks split into `rtl/` and `tb/`; verification environments split into `dv/` and `uvc/`. Keep this shape consistent across `experiments/`, `ip/`, `subsystem/`, and `system/` — don't improvise a different layout for one block.

### 2.1 `experiments/` — exploratory, pre-IP

For spikes and early architecture exploration before a block is committed to as a real IP. No formal UVM environment — a plain sanity testbench is enough.

```
hw/experiments/<block_name>/
├── src/
│   ├── rtl/          # e.g. window_buffer.sv
│   └── tb/           # <block_name>_tb.sv — plain SystemVerilog testbench, not UVM
└── sim/               # compile.f, run.do, wave.do, filelists
```

Nothing here needs to be production quality. Once a design is ready to be verified formally, move it into `ip/` — write a real UVM env there and delete the copy in `experiments/`, don't keep both.

### 2.2 `ip/` — single verified block

The main unit of work. One folder per IP, verified in isolation with its own UVM environment.

```
hw/ip/<ip_name>/
├── src/
│   ├── rtl/  (or model/)   # synthesizable RTL. model/ is for blocks that mix behavioral
│   │                       # elements with digital logic (e.g. an analog-modeled front end)
│   └── tb/                 # designer sanity tb, e.g. <ip_name>_tb.sv
└── sim/                    # common.f, compile.f, design.f, tb.f, run.do, wave.do

verif/ip/<ip_name>/
├── src/
│   ├── dv/                 # sequences, tests, top UVM tb — see section 11
│   └── uvc/                # agent, coverage, scoreboard, static — see section 11
└── sim/                    # common.f, compile.f, design.f, dv.f, uvc.f, run.do, wave.do
```

`<ip_name>` is used verbatim as the folder name on both sides, the top RTL module name (section 4), the UVM package/class prefix (section 11), and the golden-model filename in `common/model/`. Pick one name for a block and use it everywhere — don't abbreviate it differently in different places.

Use `rtl/` for pure synthesizable digital logic. Use `model/` only when the block mixes behavioral/analog-like modeling with digital logic. If a block is 100% synthesizable RTL, it belongs in `rtl/`, even if it's complex.

### 2.3 `subsystem/` — multi-block integration

Combines several `ip/` blocks into one functional subsystem. Same shape as `ip/`, with a `sub/` folder inside `rtl/` (and `tb/`) for subsystem-local wrappers that aren't standalone IPs of their own:

```
hw/subsystem/<subsystem_name>/
├── src/
│   ├── rtl/
│   │   ├── <subsystem_name>.sv     # top module — see section 4
│   │   └── sub/                    # subsystem-internal glue modules
│   └── tb/
│       └── sub/                    # matching sanity tbs for the sub/ modules
└── sim/

verif/subsystem/<subsystem_name>/
├── src/
│   ├── dv/
│   └── uvc/
└── sim/
```

### 2.4 `system/` — full design integration

Same shape again, one level up. `system/` holds a single named directory for our design:

```
hw/system/<system_name>/
├── src/
│   ├── rtl/     # <system_name>.sv (top), <system_name>_datapath.sv, ...
│   └── tb/      # <system_name>_tb.sv
└── sim/

verif/system/<system_name>/
├── src/
│   ├── dv/
│   └── uvc/
└── sim/
```

For this project, `<system_name>` is `cnn_accelerator` — so the system-level top module lives at `hw/system/cnn_accelerator/src/rtl/cnn_accelerator.sv` as `module cnn_accelerator`. Same naming rule as every other level: directory name = top module name.

### 2.5 `common/` (top-level, outside `hw/`/`verif/`)

```
common/
├── model/     # golden reference models (Python/MATLAB/C++) — see section 12
├── pkg/       # shared RTL packages: types, fixed-point defs, FSM state enums
└── script/    # automation, e.g. vrun.py
```

### 2.6 `docs/`

```
docs/
├── report/       # competition report source, results tables, FoM tracking
├── resources/     # diagrams, waveform screenshots, raw synthesis/timing/power reports
└── spec/          # requirements and the running assumptions log (see sections 12 and 16)
```

---

## 3. File Naming Conventions

|File Type|Naming Style|Example|
|---|---|---|
|RTL modules|lowercase, underscores|`window_buffer.sv`|
|Packages|lowercase, underscores, end with `_pkg.sv`|`cnn_types_pkg.sv`|
|Interfaces|lowercase, underscores, end with `_if.sv`|`pixel_stream_if.sv`|
|Designer sanity testbenches|`<module>_tb.sv`|`mac_array_tb.sv`|
|UVM env files|lowercase, role suffix (see section 11)|`mac_array_driver.svh`|
|Golden model scripts|lowercase, underscores, descriptive|`conv_golden_model.py`|

Filenames are always lowercase. The module file name must match the top module defined inside it. No CamelCase, PascalCase, or uppercase filenames.

---

## 4. Module & Instance Naming

|Type|Style|Example|
|---|---|---|
|Block top module (any level)|**same name as the directory it lives in** — no `_top` or other suffix|folder `mac_array/` -> module `mac_array` in `mac_array.sv`|
|Internal helper module (`sub/`)|lowercase, underscores, descriptive|`conv_engine`, `output_writer`|
|Instance|lowercase, descriptive, `_inst` suffix|`mac_array_inst`, `ctrl_fsm_inst`|

This rule is the same at every level — `ip/`, `subsystem/`, and `system/` all name their top module after the directory they're in, no exceptions. No `_top` suffix anywhere. Instances always end in `_inst`. Don't use `_i` as an instance suffix — reserve `_i` for loop/genvar indices, e.g. `for (i = 0; ...)`.

---

## 5. Signal Naming Conventions

### 5.1 Direction Prefix (module ports only)

|Direction|Prefix|Example|
|---|---|---|
|Input|`i_`|`i_pixel_data`|
|Output|`o_`|`o_conv_result`|
|Inout|`io_`|`io_debug_bus`|

Always **prefix**, never suffix.

### 5.2 Internal Register & Wire Prefix

| Type                            | Prefix | Example      | Case      |
| ------------------------------- | ------ | ------------ | --------- |
| Sequential (flip-flop/register) | `r_`   | `r_acc`      | lowercase |
| Combinational (wire)            | `w_`   | `w_acc_next` | lowercase |

### 5.3 Handshake / Streaming Signals

Use these consistently at every module boundary that streams data (pixels, feature-map values, etc.):

- `*_valid` — data is valid this cycle
- `*_ready` — downstream/upstream can accept data
- `*_en` — enable
- `*_err` — error flag
- `*_sop` / `*_eop` — start/end of a row or frame

Example: `i_pixel_valid`, `o_pixel_ready`, `o_frame_sop`

### 5.4 Clock & Reset

|Signal|Name|Case|
|---|---|---|
|Clock|`clk`|lowercase|
|Active-low reset|`rst_n`|lowercase|

Reset is asynchronous assert, synchronous de-assert for `rst_n`, driven through `verif/common/uvcs/rst_uvc` — one convention for the whole project, don't reinvent it per block. If a block needs a second clock domain (e.g. config clock vs. datapath clock), prefix with a domain tag (`pclk`, `cclk`) and document the crossing in `docs/report/` or `docs/spec/`.

---

## 6. Parameters, Localparams & Enums

|Type|Style|Case|Example|
|---|---|---|---|
|Parameter|Constant-like|UPPERCASE|`IMG_SIZE = 32`|
|Localparam|Constant-like|UPPERCASE|`KERNEL_SIZE = 3`|
|Enum values|Constant-like|UPPERCASE|`IDLE`, `LOAD`, `COMPUTE`|

All compile-time constants go UPPERCASE. No CamelCase for parameters — it collides with signal naming. No magic numbers anywhere in RTL — route everything through a parameter or localparam, ideally centralized in `common/pkg/`.

---

## 7. Fixed-Point & Numeric Conventions

Applies to any block with a fixed-point or quantized datapath.

|Quantity|Notes|Suggested Parameter Name|
|---|---|---|
|Input sample / activation|State signed vs. unsigned explicitly|`<SIGNAL>_WIDTH`|
|Coefficient / weight|State signed vs. unsigned explicitly|`<SIGNAL>_COEF_WIDTH`|
|Output / accumulator|State minimum width and growth vs. input|`<SIGNAL>_OUT_WIDTH`|

The competition spec fixes these for us: input pixels/activations are unsigned fixed-point (width team-chosen and justified in the report), kernel coefficients are 8-bit signed, output is 16-bit signed minimum, kernel size is N×N and programmable, stride is fixed at 1.

- Name the width parameter `<SIGNAL>_WIDTH` and, if using Qm.n format, the fractional-bit count `<SIGNAL>_FRAC`.
- Handle overflow/saturation/rounding in **one** clearly named function (e.g. `sat_round()`) — don't inline it ad hoc in multiple places.
- Any activation function (e.g. ReLU) is a separate, bypassable pipeline stage — keep it out of the accumulator so it can be disabled without touching arithmetic logic.
- Document every fixed-point choice (why this width, why this Q-format) in `docs/report/` or `docs/spec/` — see section 12 and section 16 on stating assumptions.

---

## 8. FSM Conventions

Control FSMs use a `typedef enum logic [...]` with UPPERCASE states, `r_<name>_cs` / `w_<name>_ns` naming. A representative state set for the convolution control FSM:

```
IDLE -> LOAD_WEIGHTS -> LOAD_ROW -> COMPUTE -> WRITE_OUT -> DONE (-> IDLE)
```

- Current state: `r_ctrl_cs`
- Next state: `w_ctrl_ns`
- One `always_comb` for next-state logic, one `always_ff` for the state register — never combine them.
- Every `case` statement on FSM state needs a `default:` branch that forces a safe state (section 15).

---

## 9. Standard RTL Module Template

```systemverilog
`default_nettype none

/**
 * @brief        Window Buffer
 * @desc         Generates KERNEL_SIZE x KERNEL_SIZE sliding windows from a streaming
 *               pixel input for NxN convolution.
 *
 * @assumptions  Input stream is never interrupted mid-row
 *               (i_pixel_valid stays high for a full row once asserted).
 *               Border pixels are zero-padded, not replicated.
 *
 * @notes        Line buffer depth is IMG_WIDTH * (KERNEL_SIZE-1).
 *               Resize IMG_WIDTH in cnn_types_pkg if targeting an image
 *               larger than 32x32.
 *
 * ---------------------------------------------------------------------
 * Naming Convention
 * ---------------------------------------------------------------------
 *
 * Module Ports
 *   i_              Input
 *   o_              Output
 *
 * Internal Signals
 *   w_              Combinational/internal signal
 *   r_              Registered/sequential storage
 *
 * FSM
 *   cs_             Current FSM state
 *   ns_             Next FSM state
 *
 * Types
 *   *_t             SystemVerilog typedef
 *
 * Enum Values
 *   <domain>_*      Domain-specific enum value
 *
 * Examples
 *   i_pixel_data
 *   o_window_valid
 *   w_window_ready
 *   r_line_buf
 *   cs_state
 *   ns_state
 *
 *   typedef enum logic [1:0] {
 *     WS_IDLE,
 *     WS_LOAD,
 *     WS_PROCESS,
 *     WS_DONE
 *   } window_state_t;
 *
 * ---------------------------------------------------------------------
 */

module window_buffer
  import cnn_types_pkg::*;
#(
  parameter integer PIXEL_WIDTH = cnn_types_pkg::PIXEL_WIDTH,
  parameter integer KERNEL_SIZE = cnn_types_pkg::KERNEL_SIZE,

  localparam type pixel_t = logic [PIXEL_WIDTH-1:0]
) (
  // -------------------------------------------------------------------
  // Clock / Reset
  // -------------------------------------------------------------------
  input logic clk,
  input logic rst_n,

  // -------------------------------------------------------------------
  // Inputs
  // -------------------------------------------------------------------
  input pixel_t i_pixel_data,
  input logic   i_pixel_valid,

  // -------------------------------------------------------------------
  // Outputs
  // -------------------------------------------------------------------
  output pixel_t o_window [KERNEL_SIZE][KERNEL_SIZE],
  output logic   o_window_valid
);

  // -------------------------------------------------------------------
  // FSM State Type
  // -------------------------------------------------------------------

  typedef enum logic [1:0] {
    WS_IDLE,
    WS_LOAD,
    WS_PROCESS,
    WS_DONE
  } window_state_t;

  // -------------------------------------------------------------------
  // FSM State
  // -------------------------------------------------------------------

  window_state_t cs_state;
  window_state_t ns_state;

  // -------------------------------------------------------------------
  // Combinational Signals
  // -------------------------------------------------------------------

  logic w_window_ready;

  // -------------------------------------------------------------------
  // Registered / Sequential Storage
  // -------------------------------------------------------------------

  pixel_t r_line_buf [KERNEL_SIZE-1][/* row length */];

  // -------------------------------------------------------------------
  // Combinational Logic
  // -------------------------------------------------------------------

  always_comb begin
    // Default assignment
    w_window_ready = 1'b0;

    case (cs_state)

      WS_IDLE: begin
        w_window_ready = i_pixel_valid;
      end

      WS_LOAD: begin
        w_window_ready = i_pixel_valid;
      end

      WS_PROCESS: begin
        w_window_ready = 1'b0;
      end

      WS_DONE: begin
        w_window_ready = 1'b0;
      end

      default: begin
        w_window_ready = 1'b0;
      end

    endcase
  end

  // -------------------------------------------------------------------
  // Next-State Logic
  // -------------------------------------------------------------------

  always_comb begin
    // Hold current state by default
    ns_state = cs_state;

    case (cs_state)

      WS_IDLE: begin
        if (i_pixel_valid) begin
          ns_state = WS_LOAD;
        end
      end

      WS_LOAD: begin
        ns_state = WS_PROCESS;
      end

      WS_PROCESS: begin
        ns_state = WS_DONE;
      end

      WS_DONE: begin
        ns_state = WS_IDLE;
      end

      default: begin
        ns_state = WS_IDLE;
      end

    endcase
  end

  // -------------------------------------------------------------------
  // Sequential Logic
  // -------------------------------------------------------------------

  always_ff @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin
      cs_state       <= WS_IDLE;
      o_window_valid <= 1'b0;
    end

    else begin
      cs_state       <= ns_state;
      o_window_valid <= w_window_ready;
    end

  end

  // -------------------------------------------------------------------
  // Functions
  // -------------------------------------------------------------------
  // Prefer functions over tasks for synthesizable combinational logic.

  function automatic pixel_t sat_round(
    input logic signed [PIXEL_WIDTH+7:0] value
  );

    // Saturation / rounding logic here
    return value[PIXEL_WIDTH-1:0];

  endfunction

endmodule

`default_nettype wire
```

Follow this shape for every new module:

- Import package(s) first, before the parameter list.
- Keep the parameter list and port list vertically aligned.
- If a section has nothing (e.g. no inout ports), leave it out — don't leave an empty comment.
- Add a section-divider comment (`// ---`) before each `always_comb` / `always_ff` block once a module has more than one of either.
- Restore `` `default_nettype wire `` at the end of the file after `` `default_nettype none ``, so the directive doesn't leak into files compiled after this one.
- Fill in `@assumptions` and `@notes` — see section 14.

---

## 10. Formatting Rules

- **Indentation: 2 spaces per level, no tabs.**
- One port per line.
- Signal types: always `logic` (never `reg`/`wire` in new RTL — see section 15).
- Sequential logic: `always_ff` only.
- Combinational logic: `always_comb` only.
- Line length: soft limit 100 characters.
- One blank line between logical sections; no more than one consecutive blank line.

---

## 11. UVM / Verification Environment Conventions

`verif/ip/<ip_name>/src/` is the canonical layout for every block-level verification environment.

|Component|Path pattern|Example|
|---|---|---|
|Top UVM testbench|`dv/<name>_uvm_tb.sv`|`mac_array_uvm_tb.sv`|
|Logger package|`dv/logger/<name>_logger_pkg.sv`|`mac_array_logger_pkg.sv`|
|Sequence package|`dv/sequence/<name>_sequence_pkg.sv`|`mac_array_sequence_pkg.sv`|
|Sequences|`dv/sequence/seq/<name>_seq.svh`|`mac_array_seq.svh`|
|Virtual sequences|`dv/sequence/vseq/<name>_base_vseq.svh`, `<name>_vseq.svh`|`mac_array_base_vseq.svh`|
|Tests|`dv/test/<name>_base_test.svh`, `<name>_test.svh`, `<name>_test_pkg.sv`|`mac_array_test.svh`|
|UVC top class|`uvc/<name>_uvc.svh`|`mac_array_uvc.svh`|
|UVC config|`uvc/<name>_uvc_cfg.svh`|`mac_array_uvc_cfg.svh`|
|UVC package|`uvc/<name>_uvc_pkg.sv`|`mac_array_uvc_pkg.sv`|
|Sequence item|`uvc/<name>_uvc_item.svh`|`mac_array_uvc_item.svh`|
|Agent|`uvc/agent/<name>_agent.svh`|`mac_array_agent.svh`|
|Driver / Monitor / Sequencer|`uvc/agent/components/<name>_{driver,monitor,sequencer}.svh`|`mac_array_driver.svh`|
|Coverage|`uvc/coverage/<name>_cov.svh`|`mac_array_cov.svh`|
|Scoreboard|`uvc/scoreboard/<name>_sb.svh`|`mac_array_sb.svh`|
|Scoreboard sub-components|`uvc/scoreboard/components/<name>_sb_{comparator,prd_engine,predictor}.svh`|`mac_array_sb_predictor.svh`|
|Static (interface/checker/probe)|`uvc/static/<name>_{if,checker,probe}.sv`|`mac_array_if.sv`|
|Filelist|`sim/{common,compile,design,dv,uvc}.f`|`dv.f`|

(All paths above are relative to `verif/ip/<ip_name>/src/`; `subsystem/` and `system/` use the same structure inside their own `src/`.)

When you generate a new UVC: run `generate_uvm_env.py` from `verif/_template/`, then replace every `dut_` prefix with the actual block name (e.g. `mac_array`). Don't leave `dut_` in a checked-in, non-template file.

- `clk_uvc` and `rst_uvc` in `verif/common/uvcs/` are shared across every environment — don't fork them per block. Any new shared UVC (e.g. a pixel-streaming UVC) goes in `verif/common/uvcs/`, with its own `uvc.f`, mirroring `clk_uvc/uvc.f`.
- Don't hand-edit anything under `_template/`. If the generated structure needs a permanent change, change `generate_uvm_env.py` instead so regeneration stays consistent.
- Simulator build output (build directories, waveform dumps, coverage databases, tool logs, scratch files) doesn't belong in the repo — add the relevant patterns to `.gitignore` (section 16).

---

## 12. Golden-Model & Correctness Verification

- Golden model lives in `common/model/`, written in Python, MATLAB, or C++ — pick one per block and keep that block's model entirely in that language.
- Golden model API should expose a single deterministic function, e.g. `conv2d_golden(image, kernel, stride=1) -> output`, so both the testbench and report-generation script can call it.
- Every UVM test logs: input stimulus, golden-model expected output, RTL output, and a pass/fail comparison — this feeds straight into the report's verification table.
- Use `common/script/vrun.py` (or extend it) as the single entry point that regenerates test vectors from the golden model and feeds them to simulation, so RTL and model can't quietly drift apart.
- Waveform screenshots referenced in the report should come from named, reproducible test cases (e.g. `tc_random_3x3`, `tc_edge_padding`), not ad-hoc manual runs.
- Every assumption made per the spec's "assume it, but state the assumption" instruction goes in `docs/spec/` — not just in a commit message or someone's head.

---

## 13. FPGA Synthesis, Timing & Power Reporting

- Store synthesis/implementation reports under `docs/resources/` (raw tool output) and summarize in `docs/report/`, named `<board>_<toolversion>_util.rpt`, `..._timing.rpt`, `..._power.rpt`.
    
- Track LUTs, FFs, DSPs, BRAMs, Fmax, timing status, power, and throughput (pixels/cycle) per design iteration in one table, so the Figure of Merit can be recomputed at any time:
    
    ```
    FoM = Throughput / (Power x (LUTs + 50xDSPs + 100xBRAMs))
    ```
    
- Name the parameter controlling reported throughput consistently (`THROUGHPUT_PPC` — pixels per cycle) so it's traceable from RTL parameter to report number.
    

---

## 14. Comments & Documentation

### 14.1 Module header

Every module gets a header at the top of the file (matches section 9's template):

```systemverilog
/**
 * @brief        <one-line summary>
 * @desc         <longer description of what it does and why>
 * @assumptions  <anything the module trusts about its inputs/environment that isn't
 *               obvious from the port list>
 * @notes        <anything a teammate opening this file needs — sizing, related files,
 *               non-obvious tradeoffs>
 */
```

Leave `@assumptions` / `@notes` out only if there's genuinely nothing to say. For anything with real behavior, a couple of honest sentences here save whoever opens it next a trip through `docs/spec/`.

### 14.2 Example

```systemverilog
/**
 * @brief        MAC Array
 * @desc         Performs the KERNEL_SIZE x KERNEL_SIZE multiply-accumulate for one
 *               convolution window, producing a single output pixel per COMPUTE cycle.
 * @assumptions  Kernel coefficients are already loaded and stable (see ctrl_fsm's
 *               LOAD_WEIGHTS state) before the first COMPUTE cycle begins. Overflow is
 *               handled by sat_round() in this file, not upstream.
 * @notes        Accumulator width is PIXEL_WIDTH + KERNEL_COEF_WIDTH + $clog2(KERNEL_SIZE**2)
 *               to guarantee no intermediate overflow — see docs/report for the derivation.
 *               Pairs with window_buffer.sv, which supplies the KERNEL_SIZE x KERNEL_SIZE
 *               input window each cycle.
 */
module mac_array (
  ...
);
```

Keep it this short — don't restate the port list, don't narrate the FSM line-by-line, don't duplicate the sizing derivation (that belongs in `docs/report/`). Just enough for a teammate opening the file cold to know what it trusts and where to look next.

### 14.3 Other comment rules

- **Inline comments**: only for non-obvious logic — don't restate what the code already says.
- **FSM state comments**: document what each state does and its exit condition, next to the enum declaration, not scattered through the `always_comb`.
- Keep the header in sync when behavior changes — a stale `@assumptions` is worse than none.

---

## 15. Forbidden Practices

- Mixed casing in signal names
- Multiple drivers/assignments to the same signal inside one combinational block
- `case` statements without a `default:` branch
- Unintentional latches (fully assign every output path in `always_comb`)
- Tabs instead of spaces
- `_i` used as an instance-name suffix (reserve for genvars/loop indices)
- `_top` (or any other) suffix on a block's top module — see section 4
- `reg` / `wire` keywords in new RTL — use `logic` everywhere
- Magic numbers instead of parameters/localparams
- Hand-editing files generated from `verif/_template/`
- Committing simulator build artifacts (build directories, waveform dumps, coverage databases, scratch files, tool logs) — see sections 11 and 16

---

## 16. Additional Recommendations

- **`.gitignore`**: keep a repo-level `.gitignore` covering simulator build directories, waveform dumps (`*.vcd`), coverage databases, and tool scratch/log files, so they never get committed from `verif/*/*/sim/`.
- **Linting**: run a linter (Verilator `--lint-only`, or Verible) before every commit; once a `tools/` folder exists, keep its config there and wire it into CI.
- **One module per file**: even small helper modules get their own file — keeps `design.f` filelists accurate and incremental synthesis easier to reason about.
- **Testbench-vs-RTL separation**: nothing under `hw/*/src/rtl` (or `model/`) should include simulation-only constructs (`$display`, stimulus-driving `initial` blocks) — that belongs under `tb/` or `verif/`.
- **Parameter sanity checks**: add `initial assert (KERNEL_SIZE >= 1)`-style elaboration-time checks in top-level modules so misconfiguration fails fast in simulation, not in synthesis.
- **Report traceability**: when a parameter changes for an experiment (e.g. `KERNEL_SIZE=5` vs `3`), tag the corresponding waveform/synthesis artifacts with the same suffix so results in `docs/report/` can't get mismatched.
- **Promote experiments deliberately**: when a design in `experiments/` is ready to become a real `ip/` block, move it — don't maintain two copies of the RTL in parallel.

---

## 17. Git Commit Message Conventions

Format:

```
<type>(<scope>): <short, imperative summary>

<optional body — explain why, not what>
```

**Types:**

|Type|Use for|
|---|---|
|`hw`|RTL changes|
|`verif`|Testbench, UVC, sequence, or test changes|
|`sim`|Filelists, run scripts, wave/do files|
|`docs`|Report, spec, or assumptions-log changes|
|`fix`|Bug fix in RTL or verif|
|`chore`|Repo housekeeping (.gitignore, tooling, formatting)|

**Scope** is the block name the change touches (`mac_array`, `window_buffer`, `common`, `report`). Leave it out only for changes that don't belong to one block.

**Rules:**

- Subject line under ~50 characters, imperative mood ("add", not "added" or "adds").
- One logical change per commit — don't mix an RTL fix with an unrelated filelist tweak.
- Use the body to explain _why_ the change was needed, if it isn't obvious from the subject. Wrap body text at ~72 characters.
- Reference the relevant test case or waveform file in the body when a commit fixes a bug found during verification, e.g. "Fixes tc_edge_padding failure seen in mac_array_uvm_tb."

**Examples:**

```
hw(mac_array): add saturation rounding to accumulator

fix(window_buffer): correct border padding on last row

Zero-padding wasn't applied to the final row, causing tc_edge_padding
to mismatch the golden model on the last KERNEL_SIZE-1 rows.

verif(mac_array): add tc_edge_padding sequence

docs(report): add FoM derivation for KERNEL_SIZE=3 vs 5

chore: add .gitignore for simulator build artifacts
```

---

## 18. Pre-Commit Checklist

- [ ] Filenames lowercase + underscores
- [ ] Top module name matches its containing directory (no `_top` suffix)
- [ ] Instances end with `_inst` (never `_i`)
- [ ] Ports prefixed correctly (`i_`, `o_`, `io_`)
- [ ] Internal signals prefixed correctly (`r_`, `w_`)
- [ ] Handshake signals follow `*_valid` / `*_ready` / `*_en` / `*_err` / `*_sop` / `*_eop`
- [ ] Clock = `clk`, reset = `rst_n`
- [ ] Parameters / localparams / enum values → UPPERCASE, no magic numbers
- [ ] Fixed-point widths named `<SIGNAL>_WIDTH`, saturation/rounding centralized in one function
- [ ] FSM `case` statements have a `default:` branch
- [ ] 2-space indentation, no tabs
- [ ] No `reg` / `wire` in new RTL
- [ ] Module header includes `@assumptions` / `@notes` where there's anything worth saying
- [ ] UVM component paths/suffixes match section 11 table
- [ ] Golden-model comparison logged for every test case
- [ ] Synthesis/timing/power reports saved under `docs/resources/` + summarized in `docs/report/`
- [ ] No simulator build artifacts staged for commit (check `.gitignore`)
- [ ] All assumptions documented in `docs/spec/`
- [ ] Commit message follows section 17's format