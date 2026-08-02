class dut_uvc_item extends uvm_sequence_item;

   `uvm_object_utils(dut_uvc_item)
   `include "uvm_print_macros.svh"
   // STIMULUS FIELDS ───────────────────────────────────────────────────────────
   
   // GEN:BEGIN INPUT
   rand bit [15:0] i_din;
   // GEN:END

   // RESPONSE FIELDS ───────────────────────────────────────────────────────────

   // GEN:BEGIN OUTPUT
   logic [15:0] o_dout;
   // GEN:END

   // DEBUG FIELDS ──────────────────────────────────────────────────────────────
   realtime d_monitor_time;
   int      d_predictor_id;

   // PUBLIC API ────────────────────────────────────────────────────────────────

   extern function new(input string name = "dut_uvc_item");

   extern virtual function dut_uvc_item set(
      // GEN:BEGIN INPUT LIST
      input bit [15:0] i_din
      // GEN:END
   );
   extern virtual function void do_copy(input uvm_object rhs);
   extern virtual function bool do_compare(input uvm_object rhs, uvm_comparer comparer);

   extern virtual function string input2string();
   extern virtual function string output2string();
   extern virtual function string convert2string();
   extern virtual function string compare2string(input dut_uvc_item act_tr, input bit passed);

endclass


// METHOD DEFINITIONS ────────────────────────────────────────────────────────────


// CONSTRUCTOR ──────────────────────────────────────────────────────────────────

function dut_uvc_item::new(input string name = "dut_uvc_item");
   super.new(name);
endfunction


// TODO SET ──────────────────────────────────────────────────────────────────────────

function dut_uvc_item dut_uvc_item::set(
   // GEN:BEGIN INPUT LIST
   input bit [15:0] i_din
   // GEN:END
);

   // GEN:BEGIN INPUT
   this.i_din = i_din;
   // GEN:END
   
   return this;
endfunction


// TODO COPY ─────────────────────────────────────────────────────────────────────────

function void dut_uvc_item::do_copy(input uvm_object rhs);

   dut_uvc_item tr;

   if (!$cast(tr, rhs)) `log_cast_err("do_copy() cast to dut_uvc_item failed")

   super.do_copy(rhs);

   // GEN:BEGIN INPUT
   i_din  = tr.i_din;
   // GEN:END

   // GEN:BEGIN OUTPUT
   o_dout = tr.o_dout;
   // GEN:END

endfunction


// COMPARE ──────────────────────────────────────────────────────────────────────

function bit dut_uvc_item::do_compare(input uvm_object rhs, uvm_comparer comparer);

   dut_uvc_item tr;
   bit          eq;

   if (!$cast(tr, rhs)) `log_cast_err("do_compare() cast to dut_uvc_item failed")

   eq = super.do_compare(rhs, comparer);

   // GEN:BEGIN OUTPUT
   eq &= (o_dout === tr.o_dout);
   // GEN:END

   return eq;

endfunction


// INPUT TO STRING ──────────────────────────────────────────────────────────────
//
//  ┌──────────────────────┬────────────────────────────────────────────────┐
//  │ INPUT                |                                                │
//  ├──────────────────────┼────────────────────────────────────────────────┤
//  │ i_din                │ 0xABCD (1010101111001101)                      │
//  └──────────────────────┴────────────────────────────────────────────────┘

function string dut_uvc_item::input2string();

   string s = "\n";

   s = {s, `SIG_TOP};
   s = {s, `SIG_LABEL("INPUT")};
   s = {s, `SIG_MID};

   // GEN:BEGIN INPUT
   s = {s, `signal_to_string(i_din, "i_din")};
   // GEN:END

   s = {s, `SIG_BOT};

   return s;

endfunction


// OUTPUT TO STRING ────────────────────────────────────────────────────────────
//
//  ┌──────────────────────┬────────────────────────────────────────────────┐
//  │ OUTPUT               |                                                │
//  ├──────────────────────┼────────────────────────────────────────────────┤
//  │ o_dout                 │ 0x1234 (0001001000110100)                      │
//  └──────────────────────┴────────────────────────────────────────────────┘

function string dut_uvc_item::output2string();

   string s = "\n";

   s = {s, `SIG_TOP};
   s = {s, `SIG_LABEL("OUTPUT")};
   s = {s, `SIG_MID};

   // GEN:BEGIN OUTPUT
   s = {s, `signal_to_string(o_dout, "o_dout")};
   // GEN:END

   s = {s, `SIG_BOT};

   return s;

endfunction


// CONVERT TO STRING ────────────────────────────────────────────────────────────
//
//
//  ┌───────────────────────────────────────────────────────────────────────┐
//  │ dut_uvc_item                                                          │
//  ├───────────────────────────────────────────────────────────────────────┤
//  │ INPUT                                                                 │  ← input2string()
//  ├──────────────────────┼────────────────────────────────────────────────┤
//  │ i_din                  │ 0xABCD (1010101111001101)                    │
//  └──────────────────────┴────────────────────────────────────────────────┘
//  ┌──────────────────────┬────────────────────────────────────────────────┐
//  │ OUTPUT                                                                │  ← output2string()
//  ├──────────────────────┼────────────────────────────────────────────────┤
//  │ o_dout                 │ 0x1234 (0001001000110100)                    │
//  └──────────────────────┴────────────────────────────────────────────────┘

function string dut_uvc_item::convert2string();

   string s;

   s = "\n";

   // ── title ──────────────────────────────────────────────────────────────
   s = {s, $sformatf("┌%0s┐\n", {(`SIG_INNER) {"─"}})};
   s = {s, `SIG_LABEL("dut_uvc_item")};
   s = {s, `SIG_MERGE_MID};

   s = {s, input2string()};
   s = {s, output2string()};

   return s;

endfunction


// COMPARE TO STRING ────────────────────────────────────────────────────────────
//
//  ┌────────────────────────────────────────────────────────────────────────────┐
//  │ DUT SCOREBOARD [PASS]                                                      │
//  ├────────────────────────────────────────────────────────────────────────────┤
//  │ INPUT STIMULUS                                                             │
//  ├────────────────────────────────────────────────────────────────────────────┤
//  │                                                                            │
//  ├────────────────────────────────────────────────────────────────────────────┤
//  │ OUTPUT COMPARISON                                                          │
//  ├──────────────────────┬────────────────────────┬────────────────────────┬───┤
//  │ Field                │ Expected               │ Actual                 │   │
//  ├──────────────────────┼────────────────────────┼────────────────────────┼───┤
//  │ o_dout               │ 0x1234                 │ 0x1234                 │   │
//  └──────────────────────┴────────────────────────┴────────────────────────┴───┘

function string dut_uvc_item::compare2string(input dut_uvc_item act_tr, input bit passed);

   string s;
   string title;

   title = passed ? "DUT SCOREBOARD [PASS]" : "DUT SCOREBOARD [FAIL]";

   s = "\n";

   // ── title ──────────────────────────────────────────────────────────────
   s = {s, `CMP_FULL_TOP};
   s = {s, `CMP_LABEL(title)};

   // ── INPUT STIMULUS – fully delegated, nothing to edit here ────────────
   s = {s, `CMP_MERGE_MID};
   s = {s, `CMP_LABEL("INPUT STIMULUS")};
   s = {s, `CMP_MERGE_MID};
   s = {s, input2string()};  // ← single source of truth for input fields

   // ── OUTPUT COMPARISON ──────────────────────────────────────────────────
   s = {s, `CMP_MERGE_MID};
   s = {s, `CMP_LABEL("OUTPUT COMPARISON")};
   s = {s, `CMP_TOP};

   s = {s, $sformatf(`CMP_ROW_FMT, "Field", "Expected", "Actual", "Status")};
   s = {s, `CMP_MID};

   // GEN:BEGIN OUTPUT
   s = {s, `compare_format(o_dout, "o_dout")};
   // GEN:END
  

   s = {s, `CMP_BOT};

   return s;

endfunction
