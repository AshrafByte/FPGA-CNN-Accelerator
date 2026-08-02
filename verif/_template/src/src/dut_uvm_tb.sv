

module dut_uvm_tb;
   timeunit 1ps / 1fs;

   import uvm_pkg::*;
   import dut_test_pkg::*;

   // SIGNALS ────────────────────────────────────────────────────────────────────


   clk_if clk_vif ();
   rst_if rst_vif ();

   // phy_clks #(
   //    .PCLK_MULT(PCLK_MULT),
   //    .BCLK_MULT(BCLK_MULT),
   //    .SCLK_DIV(SCLK_DIV),
   //    .LOCK_CYCLES(LOCK_CYCLES)
   // ) phy_clks_instance (
   //    .ref_clk(ref_clk),
   //    .rst_n(rst_n),
   //    .pll_lock(pll_lock),
   //    .pclk(pclk),
   //    .bclk(bclk),
   //    .sclk(sclk)
   // );

   // rst_sync #(
   //    .NUM_STAGES(2)
   // ) rst_sync_inst (
   //    .i_clk       (clk_vif.clk),
   //    .i_rst_n     (rst_vif.rst_n),
   //    .o_rst_n_sync(rst_vif.rst_n_sync)
   // );

   dut_if dut_vif (
      .clk  (clk_vif.clk),
      .rst_n(rst_vif.rst_n)
   );


   dut dut_instance (
      .clk  (clk_vif.clk),
      .rst_n(rst_vif.rst_n),

      // GEN:BEGIN INPUT LIST
      .i_din(dut_vif.i_din),
      // GEN:END

      // GEN:BEGIN OUTPUT LIST
      .o_dout(dut_vif.o_dout)
      // GEN:END
   );


   // UVM BOOTSTRAP ──────────────────────────────────────────────────────────────

   initial begin

      uvm_config_db#(virtual dut_if)::set(null, "uvm_test_top", "dut_vif", dut_vif);
      uvm_config_db#(virtual rst_if)::set(null, "uvm_test_top", "rst_vif", rst_vif);
      uvm_config_db#(virtual clk_if)::set(null, "uvm_test_top", "clk_vif", clk_vif);

      run_test("dut_test");
   end

endmodule
