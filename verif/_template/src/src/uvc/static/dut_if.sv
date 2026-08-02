//----------------------------------------------------------------------
// DUT Interface
// 
//----------------------------------------------------------------------

interface dut_if
   import serdes_common_pkg::*;
(
   input logic clk,
   input logic rst_n
);

   // STRUCTURAL SIGNALS ────────────────────────────────────────────────────────

   // GEN:BEGIN INPUT
   logic [15:0] i_din;
   // GEN:END

   // GEN:BEGIN OUTPUT
   logic [15:0] o_dout;
   // GEN:END

   // ASSERTION ─────────────────────────────────────────────────────────────────

   // dut_checker dut_checker_instance (
   //    .clk  (clk),
   //    .rst_n(rst_n),
   //    .i_din  (i_din),
   //    .o_dout (o_dout)
   // );

   // CLOCKING BLOCKS ─────────────────────────────────────────────────────────────

   clocking drv_cb @(posedge clk);

      default output #(uvm_common_pkg::TDRIVE_PLACE_HOLDER);

      // GEN:BEGIN INPUT
      output i_din;
   // GEN:END

   endclocking

   clocking mon_cb @(posedge clk);

      default input #1step;

      // GEN:BEGIN INPUT
      input i_din;
      // GEN:END

      // GEN:BEGIN OUTPUT
      input o_dout;
   // GEN:END

   endclocking

   // MODPORTS ────────────────────────────────────────────────────────────────────

   modport drv_mp(clocking drv_cb,
       input rst_n,
       import task drive_idle(),
       import task wait_reset_release(),
       import task wait_reset_assert(),
       import task wait_reset_resolve()
   );

   modport mon_mp(clocking mon_cb,
       input rst_n,
       import task wait_reset_release(),
       import task wait_reset_assert(),
       import task wait_reset_resolve()
   );

   // PUBLIC TASKS ────────────────────────────────────────────────────────────────

   task automatic wait_reset_resolve();
      wait (!$isunknown(rst_n));
      drive_idle();
   endtask

   task automatic wait_reset_assert();
      if (rst_n === 1'b0) return;
      @(negedge rst_n);
   endtask

   task automatic wait_reset_release();
      if (rst_n === 1'b1) return;
      @(posedge rst_n);
   endtask


   task automatic drive_idle();
      // GEN:BEGIN INPUT
      drv_cb.i_din <= 'd0;
      // GEN:END
   endtask

endinterface
