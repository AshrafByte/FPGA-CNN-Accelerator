//------------------------------------------------------------------------------
// Class: fifo_scoreboard
//
// Description:
//   Generic ordered-stream scoreboard: tracks values expected to be observed
//   on a DUT's output, in order, and reports a mismatch/underflow the moment
//   one occurs. Not specific to output_fifo — reusable against any module
//   that produces a valid-gated stream matching a known write order.
//------------------------------------------------------------------------------
class fifo_scoreboard #(type T = logic [7:0]);

   local T   expected_q[$];
   local int write_count;
   local int read_count;
   local int error_count;

   function new();
      write_count = 0;
      read_count  = 0;
      error_count = 0;
   endfunction

   function void report_error(string message);
      error_count++;
      $display("[FAIL] %s", message);
   endfunction

   // call whenever the driver pushes a new value into the DUT
   function void record_write(T value);
      expected_q.push_back(value);
      write_count++;
   endfunction

   // call every cycle; only acts when valid is high
   function void check_output(logic valid, T actual);
      T expected;
      if (!valid) return;

      if (expected_q.size() == 0) begin
         report_error("output asserted valid but no data was ever written");
         return;
      end

      expected = expected_q.pop_front();
      read_count++;
      if (actual !== expected)
         report_error($sformatf("read %0d: got %0d, expected %0d",
                                 read_count, actual, expected));
   endfunction

   // call whenever a signal that should never be valid yet is checked
   // (e.g. before a prefill threshold is reached)
   function void check_not_valid(logic valid, string msg);
      if (valid)
         report_error($sformatf("output asserted valid unexpectedly: %s", msg));
   endfunction

   function int pending();
      return expected_q.size();
   endfunction

   function int get_error_count();
      return error_count;
   endfunction

   function int get_read_count();
      return read_count;
   endfunction

   function int get_write_count();
      return write_count;
   endfunction

endclass

//------------------------------------------------------------------------------
// Interface: output_fifo_bfm
//
// Description:
//   Bus-functional model for output_fifo's write side. Bundles the DUT-facing
//   signals together with the timing-correct tasks needed to drive them, so
//   the testbench module only issues intent ("write this value", "idle for a
//   cycle") without repeating clock-edge/timing detail at every call site.
//
// Notes:
//   - Read-side signals (o_data_out/o_valid_out) are exposed here too, since
//     they belong to the same DUT connection, but sampling/checking logic
//     intentionally stays in fifo_scoreboard, not in this BFM — driving and
//     checking are different responsibilities and are kept separate.
//------------------------------------------------------------------------------
interface output_fifo_bfm #(
   parameter int PIXEL_WIDTH = 8
)(
   input logic clk
);

   logic                   rst_n;
   logic                   i_valid_in;
   logic [PIXEL_WIDTH-1:0] i_data_in;
   logic                   i_last_in;
   logic [PIXEL_WIDTH-1:0] o_data_out;
   logic                   o_valid_out;
   logic                   o_last_out;

   task automatic init_signals();
      i_valid_in = 1'b0;
      i_data_in  = '0;
      i_last_in  = 1'b0;
   endtask

   // drives one value for exactly one clock edge; last marks a frame's final entry
   task automatic write_one(input logic [PIXEL_WIDTH-1:0] value, input logic last = 1'b0);
      i_valid_in <= 1'b1;
      i_data_in  <= value;
      i_last_in  <= last;
      @(posedge clk);
   endtask

   // deasserts valid for exactly one clock edge - models an upstream gap
   task automatic write_idle_cycle();
      i_valid_in <= 1'b0;
      i_last_in  <= 1'b0;
      @(posedge clk);
   endtask

endinterface

//------------------------------------------------------------------------------
// Module: output_fifo_tb
//
// Description:
//   Directed test for output_fifo: verifies no output is produced before
//   PREFILL_THRESHOLD is reached, then drives a gapped write stream via
//   output_fifo_bfm and confirms every value drains out in order, with no
//   loss or reordering, and that o_last marks the frame's last value. A second
//   frame follows without a reset and must prefill and drain the same way.
//------------------------------------------------------------------------------
module output_fifo_tb;

   import tb_util_pkg::*;

   localparam time CLK_PERIOD        = 10ns;
   localparam int  PIXEL_WIDTH       = 8;
   localparam int  DEPTH             = 8;
   localparam int  PREFILL_THRESHOLD = 4;
   localparam int  WRITE_COUNT       = 20;   // values per frame
   localparam int  FRAMES            = 2;
   localparam int  TIMEOUT_CYCLES    = 200;

   logic clk;

   fifo_scoreboard #(logic [PIXEL_WIDTH-1:0]) tb_sb;

   output_fifo_bfm #(
      .PIXEL_WIDTH(PIXEL_WIDTH)
   ) bfm (
      .clk(clk)
   );

   output_fifo #(
      .PIXEL_WIDTH      (PIXEL_WIDTH),
      .DEPTH            (DEPTH),
      .PREFILL_THRESHOLD(PREFILL_THRESHOLD)
   ) u_dut (
      .clk        (clk),
      .rst_n      (bfm.rst_n),
      .i_valid (bfm.i_valid_in),
      .i_data  (bfm.i_data_in),
      .i_last  (bfm.i_last_in),
      .o_data (bfm.o_data_out),
      .o_valid(bfm.o_valid_out),
      .o_last (bfm.o_last_out)
   );

   clk_gen #(
      .CLK_PERIOD(CLK_PERIOD)
   ) u_clk_gen (
      .clk(clk)
   );

   // One read-side check per cycle: value order through the scoreboard, and
   // o_last exactly on the last read of every frame.
   function automatic void check_cycle();
      tb_sb.check_output(bfm.o_valid_out, bfm.o_data_out);
      if (bfm.o_last_out === 1'b1 && bfm.o_valid_out !== 1'b1)
         tb_sb.report_error("o_last asserted without o_valid");
      else if (bfm.o_valid_out === 1'b1 &&
               ((bfm.o_last_out === 1'b1) != ((tb_sb.get_read_count() % WRITE_COUNT) == 0)))
         tb_sb.report_error($sformatf("o_last=%0b on read %0d (frames of %0d)",
                                      bfm.o_last_out, tb_sb.get_read_count(), WRITE_COUNT));
   endfunction

   // Drives writes first..first+count-1 through the BFM, occasionally skipping
   // a cycle to model the kind of upstream gap this FIFO is meant to absorb.
   // The last write of a frame carries i_last. Records every write into the
   // scoreboard so it knows what to expect back.
   task automatic drive_writes(input int first, input int count, input int gap_every = 5);
      $display("[TEST] Driving %0d values, with a gap every %0d writes", count, gap_every);
      for (int i = first; i < first + count; i++) begin
         bfm.write_one(PIXEL_WIDTH'(i), (i % WRITE_COUNT) == WRITE_COUNT - 1);
         tb_sb.record_write(PIXEL_WIDTH'(i));
         if ((i % gap_every) == (gap_every - 1))
            bfm.write_idle_cycle();
      end
      bfm.i_valid_in <= 1'b0;
      bfm.i_last_in  <= 1'b0;
   endtask

   // waits until every written value has been drained, watching for a stall,
   // then requires the output to stay quiet
   task automatic drain_and_check(input int timeout_cycles);
      int idle_cycles = 0;
      $display("[TEST] Draining remaining %0d buffered value(s)", tb_sb.pending());
      while ((tb_sb.pending() != 0) && (idle_cycles < timeout_cycles)) begin
         @(posedge clk);
         check_cycle();
         idle_cycles = bfm.o_valid_out ? 0 : idle_cycles + 1;
      end
      if (tb_sb.pending() != 0)
         tb_sb.report_error($sformatf("timed out with %0d value(s) still undrained",
                                       tb_sb.pending()));
      repeat (PREFILL_THRESHOLD + 4) begin
         @(posedge clk);
         tb_sb.check_not_valid(bfm.o_valid_out, "after the frame drained");
      end
   endtask

   // One frame of WRITE_COUNT values: nothing drains before PREFILL_THRESHOLD
   // entries, then every value leaves in order and o_last marks the last one.
   // Frames after the first run without a reset, so they prove that reading
   // the last entry re-arms the prefill.
   task automatic run_frame(input int frame);
      int base = frame * WRITE_COUNT;
      $display("[TEST] Frame %0d", frame);

      // the first PREFILL_THRESHOLD-1 writes must not drain
      for (int i = 0; i < PREFILL_THRESHOLD - 1; i++) begin
         bfm.write_one(PIXEL_WIDTH'(base + i));
         tb_sb.record_write(PIXEL_WIDTH'(base + i));
         tb_sb.check_not_valid(bfm.o_valid_out, "before PREFILL_THRESHOLD reached");
      end

      // remaining writes, with gaps, run concurrently with output checking
      fork
         drive_writes(base + PREFILL_THRESHOLD - 1, WRITE_COUNT - (PREFILL_THRESHOLD - 1), 5);
         begin: monitor
            forever begin
               @(posedge clk);
               check_cycle();
            end
         end: monitor
      join_any
      disable monitor;

      drain_and_check(TIMEOUT_CYCLES);
   endtask

   initial begin: test_sequence
      tb_sb = new();
      bfm.init_signals();

      $display("============================================================");
      $display("[TEST] output_fifo test started (DEPTH=%0d, PREFILL=%0d, %0d frames of %0d)",
                DEPTH, PREFILL_THRESHOLD, FRAMES, WRITE_COUNT);

      apply_reset(clk, 5 ,bfm.rst_n);

      for (int f = 0; f < FRAMES; f++)
         run_frame(f);

      $display("============================================================");
      if (tb_sb.get_error_count() == 0)
         $display("[PASS] output_fifo: %0d value(s) verified over %0d frame(s), one reset",
                   tb_sb.get_read_count(), FRAMES);
      else
         $display("[FAIL] output_fifo completed with %0d error(s)",
                   tb_sb.get_error_count());
      $display("============================================================");

      $finish(tb_sb.get_error_count() == 0 ? 0 : 1);
   end: test_sequence

endmodule