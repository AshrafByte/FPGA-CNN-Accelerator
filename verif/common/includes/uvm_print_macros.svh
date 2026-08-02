//==============================================================================
// FILE : uvm_print_macros.svh
// PATH : verif/common/macros/uvm_print_macros.svh
//
// PURPOSE
//   Centralised table-formatting macros for UVM sequence-item print methods
//   (input2string, output2string, convert2string, compare2string).
//
//   Include this file – never import it into a package, since `define macros
//   are preprocessor directives and are not scoped to packages.
//
// USAGE
//   In every file that needs these macros:
//
//     `include "uvm_print_macros.svh"
//
//   The include-guard prevents double-expansion when multiple files in the
//   same compilation unit include this header.
//
// SIGNAL ROW MACROS
//   `signal_to_string(signal, "label")
//       One display row for the signal/value table.
//       Uses %h / %b format specifiers which zero-pad to the signal's
//       declared width in all IEEE-compliant simulators (Questa, VCS, Xcelium).
//
//   `compare_format(signal, "label")
//       One comparison row (expected vs actual) for the scoreboard table.
//       Requires a local variable named exp_tr of the same item type to
//       be in scope at the call site.
//
// COLUMN-WIDTH TUNING
//   To resize the tables, change the five `define constants in the
//   "COLUMN WIDTHS" section, then update the matching "FORMAT STRINGS"
//   section directly below it.  The format strings must be kept in sync
//   with the width constants by hand – this is intentional: the literals
//   avoid the %-*s dynamic-width specifier which is not supported by
//   Questa/VCS/Xcelium.
//
//   Width constants and their derived format strings:
//
//   NAME_W  = 20   →  %-20s
//   VAL_W   = 46   →  %-46s
//   EXP_W   = 22   →  %-22s
//   ACT_W   = 22   →  %-22s
//   STAT_W  =  6   →  %-6s
//   SIG_INNER = NAME_W + VAL_W + 3         = 69  →  %-67s  (inner = 69-2)
//   CMP_INNER = NAME_W+EXP_W+ACT_W+STAT_W+12   = 82  →  %-80s  (inner = 82-2)
//
//   VAL_W sizing reference  (value column – hex + binary display):
//     Format produced: "0xHHHH (BBBB…B)"
//     ┌──────────┬────────────┬──────────────────┬─────────────────────┐
//     │ Sig bits │ Hex digits │ Formatted length │ Fits VAL_W=46?      │
//     ├──────────┼────────────┼──────────────────┼─────────────────────┤
//     │  4       │  1         │  9               │ yes                 │
//     │  8       │  2         │ 14               │ yes                 │
//     │ 16       │  4         │ 24               │ yes                 │
//     │ 24       │  6         │ 34               │ yes                 │
//     │ 32       │  8         │ 44               │ yes (tight fit)     │
//     │ 64       │ 16         │ 84               │ no – increase to 88 │
//     └──────────┴────────────┴──────────────────┴─────────────────────┘
//
//==============================================================================

`ifndef UVM_PRINT_MACROS_SVH
`define UVM_PRINT_MACROS_SVH

// ─────────────────────────────────────────────────────────────────────────────
// COLUMN WIDTHS  –  single source of truth (integers, used for replication)
//
//  When you change a value here, update the matching FORMAT STRINGS below.
// ─────────────────────────────────────────────────────────────────────────────

`define NAME_W   20   // signal name column  – fits names up to 20 chars
`define VAL_W    46   // hex+binary column   – fits signals up to 32 bits
`define EXP_W    22   // expected column     – fits hex up to 64-bit (18 chars)
`define ACT_W    22   // actual column       – same as EXP_W
`define STAT_W    6   // status column       – "PASS" / "FAIL"

// Derived totals  (each internal │ separator costs 3 chars: space+bar+space)
`define SIG_INNER  (`NAME_W + `VAL_W  + 5)                        // 69
`define CMP_INNER  (`NAME_W + `EXP_W + `ACT_W + `STAT_W + 11)    // 82

// ─────────────────────────────────────────────────────────────────────────────
// FORMAT STRINGS  –  literal widths baked in (no %-*s dynamic specifier)
//
//  These MUST be kept in sync with the integer constants above.
//  SIG_LABEL_FMT  uses SIG_INNER-2 = 67
//  SIG_ROW_FMT    uses NAME_W=20, VAL_W=46
//  CMP_LABEL_FMT  uses CMP_INNER-2 = 80
//  CMP_ROW_FMT    uses NAME_W=20, EXP_W=22, ACT_W=22, STAT_W=6
// ─────────────────────────────────────────────────────────────────────────────

`define SIG_LABEL_FMT   "│ %-67s   │\n"
`define SIG_ROW_FMT     "│ %-20s │ %-46s │\n"
`define CMP_LABEL_FMT   "│ %-79s │\n"
`define CMP_ROW_FMT     "│ %-20s │ %-22s │ %-22s │ %-6s │\n"

// ─────────────────────────────────────────────────────────────────────────────
// SIGNAL / VALUE TABLE BORDERS
//   Used by input2string, output2string, and convert2string.
// ─────────────────────────────────────────────────────────────────────────────

// ┌─…─┬─…─┐
`define SIG_TOP \
   $sformatf("┌%0s┬%0s┐\n", \
      {(`NAME_W+2){"─"}}, \
      {(`VAL_W +2){"─"}})

// ├─…─┼─…─┤
`define SIG_MID \
   $sformatf("├%0s┼%0s┤\n", \
      {(`NAME_W+2){"─"}}, \
      {(`VAL_W +2){"─"}})

// └─…─┴─…─┘
`define SIG_BOT \
   $sformatf("└%0s┴%0s┘\n", \
      {(`NAME_W+2){"─"}}, \
      {(`VAL_W +2){"─"}})

// ├─…──────────────────────────────────────────┤  (full-width section divider)
`define SIG_MERGE_MID \
   $sformatf("├%0s┤\n", {(`SIG_INNER){"─"}})

// │ label ──────────────────────────────────── │  (full-width text row)
`define SIG_LABEL(label) \
   $sformatf(`SIG_LABEL_FMT, label)

// ─────────────────────────────────────────────────────────────────────────────
// SIGNAL ROW MACRO
//
//   `signal_to_string(signal, "label")
//
//   Emits:  │ label                │ 0xHHHH (BBBB…B)                        │
//
//   %h zero-pads to the signal's declared width in all IEEE-compliant
//   simulators.  %b does the same for binary.  No * dynamic width needed.
// ─────────────────────────────────────────────────────────────────────────────

`define signal_to_string(signal, str) \
   $sformatf(`SIG_ROW_FMT, \
      str, \
      $sformatf("0x%h (%b)", signal, signal))

// ─────────────────────────────────────────────────────────────────────────────
// COMPARISON TABLE BORDERS
//   Used by compare2string.
// ─────────────────────────────────────────────────────────────────────────────

// ┌─…─┬─…─┬─…─┬─…─┐
`define CMP_TOP \
   $sformatf("┌%0s┬%0s┬%0s┬%0s┐\n", \
      {(`NAME_W+2){"─"}}, \
      {(`EXP_W +2){"─"}}, \
      {(`ACT_W +2){"─"}}, \
      {(`STAT_W+2){"─"}})

// ├─…─┼─…─┼─…─┼─…─┤
`define CMP_MID \
   $sformatf("├%0s┼%0s┼%0s┼%0s┤\n", \
      {(`NAME_W+2){"─"}}, \
      {(`EXP_W +2){"─"}}, \
      {(`ACT_W +2){"─"}}, \
      {(`STAT_W+2){"─"}})

// └─…─┴─…─┴─…─┴─…─┘
`define CMP_BOT \
   $sformatf("└%0s┴%0s┴%0s┴%0s┘\n", \
      {(`NAME_W+2){"─"}}, \
      {(`EXP_W +2){"─"}}, \
      {(`ACT_W +2){"─"}}, \
      {(`STAT_W+2){"─"}})

// ├─…──────────────────────────────────────────────────────┤  (full-width)
`define CMP_MERGE_MID \
   $sformatf("├%0s┤\n", {(`CMP_INNER){"─"}})

// ┌─…──────────────────────────────────────────────────────┐  (full-width top)
`define CMP_FULL_TOP \
   $sformatf("┌%0s┐\n", {(`CMP_INNER){"─"}})

// │ label ────────────────────────────────────────────────── │
`define CMP_LABEL(label) \
   $sformatf(`CMP_LABEL_FMT, label)

// ─────────────────────────────────────────────────────────────────────────────
// COMPARISON ROW MACRO
//
//   `compare_format(signal, "label")
//
//   Emits:  │ label  │ 0xHHHH (expected) │ 0xHHHH (actual) │ PASS │
//
//   Requires a local variable exp_tr of the same sequence-item type to be
//   in scope at the call site.
//   Only hex is shown (no binary) so expected and actual fit side-by-side.
// ─────────────────────────────────────────────────────────────────────────────

`define compare_format(signal, str) \
   $sformatf(`CMP_ROW_FMT, \
      str, \
      $sformatf("0x%h", signal), \
      $sformatf("0x%h", act_tr.signal), \
      (act_tr.signal === signal) ? "PASS" : "FAIL")

`endif // UVM_PRINT_MACROS_SVH
