//------------------------------------------------------------------------------
// Testbench: kernel_register_tb
//
// Description:
//   Self-checking test of the shift-loaded kernel register, including the
//   behaviour conv_system relies on to change kernels between frames without
//   a reset:
//     1. reset clears every weight and o_ready
//     2. a load split over two bursts raises o_ready only after N^2 writes,
//        with the first weight written at index 0
//     3. a second full load without reset replaces every weight and o_ready
//        stays high once it completes
//     4. an over-long load (N^2 + 1 writes) leaves o_ready low
//     5. the extra write counted as the first of a new load: N^2 - 1 more
//        writes raise o_ready again
//     6. write enable low holds the weights
//     7. reset clears everything again
//------------------------------------------------------------------------------
module kernel_register_tb;

   import tb_util_pkg::apply_reset;

   localparam time CLK_PERIOD  = 10ns;
   localparam int  PIXEL_WIDTH = 8;
   localparam int  WINDOW_SIZE = 3;
   localparam int  E           = WINDOW_SIZE ** 2;

   typedef logic signed [PIXEL_WIDTH-1:0] weight_t;

   logic    clk;
   logic    rst_n      = 1'b0;
   logic    i_write_en = 1'b0;
   weight_t i_weight   = '0;
   weight_t o_weights [E];
   logic    o_ready;

   weight_t tb_written [$];   // every weight written since the last reset, in order
   int      tb_errors;

   clk_gen #(.CLK_PERIOD(CLK_PERIOD)) u_clk_gen (.clk(clk));

   kernel_register #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .WINDOW_SIZE(WINDOW_SIZE)
   ) u_dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .i_write_en(i_write_en),
      .i_weight (i_weight),
      .o_weights(o_weights),
      .o_ready  (o_ready)
   );

   // Drives `count` writes; values are derived from `seed` so every load differs.
   task automatic write_weights(int count, int seed);
      for (int i = 0; i < count; i++) begin
         i_write_en <= 1'b1;
         i_weight   <= weight_t'((seed * 37 + i * 11) & 8'hFF);
         tb_written.push_back(weight_t'((seed * 37 + i * 11) & 8'hFF));
         @(posedge clk);
      end
      i_write_en <= 1'b0;
      @(posedge clk);
   endtask

   // The register holds the last E weights written, oldest at index 0.
   task automatic check(string step, bit expect_ready, bit expect_zero = 1'b0);
      weight_t expected;
      @(negedge clk);
      if (o_ready !== expect_ready) begin
         $display("[FAIL] %s: o_ready=%0b, expected %0b", step, o_ready, expect_ready);
         tb_errors++;
      end
      for (int k = 0; k < E; k++) begin
         expected = expect_zero ? weight_t'(0) : tb_written[tb_written.size() - E + k];
         if (o_weights[k] !== expected) begin
            $display("[FAIL] %s: o_weights[%0d]=%0d, expected %0d", step, k, o_weights[k], expected);
            tb_errors++;
         end
      end
      if (tb_errors == 0) $display("[PASS] %s", step);
   endtask

   initial begin
      $display("============================================================");
      $display("[TEST] kernel_register test started (WINDOW_SIZE=%0d)", WINDOW_SIZE);

      apply_reset(clk, 5, rst_n);
      check("reset clears weights and o_ready", 1'b0, 1'b1);

      write_weights(5, 1);
      @(negedge clk);
      if (o_ready !== 1'b0) begin
         $display("[FAIL] partial load: o_ready high after 5 writes");
         tb_errors++;
      end
      write_weights(E - 5, 2);
      check("load in two bursts, first weight at index 0", 1'b1);

      write_weights(E, 3);
      check("reload without reset", 1'b1);

      write_weights(E + 1, 4);
      check("over-long load leaves o_ready low", 1'b0);

      write_weights(E - 1, 5);
      check("extra write starts a new load", 1'b1);

      repeat (4) @(posedge clk);
      check("write enable low holds the weights", 1'b1);

      apply_reset(clk, 3, rst_n);
      tb_written.delete();
      check("reset clears everything again", 1'b0, 1'b1);

      $display("============================================================");
      if (tb_errors == 0) $display("[PASS] kernel_register: all checks passed");
      else                $display("[FAIL] kernel_register: %0d error(s)", tb_errors);
      $display("============================================================");
      $finish(tb_errors == 0 ? 0 : 1);
   end

endmodule
