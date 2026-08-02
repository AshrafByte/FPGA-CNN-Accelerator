interface rst_if;

   timeunit 1ps / 1fs;

   import uvm_pkg::*;
   logic rst_n;
   logic rst_n_sync;
   // ─────────────────────────────────────────────
   // INTERNAL CONFIG (optional extension point)
   // ─────────────────────────────────────────────

   // ─────────────────────────────────────────────
   // RESET CONTROL BFM TASKS
   // ─────────────────────────────────────────────

   task drive_idle();
      rst_n = 1'bx;
   endtask


   task apply_reset_pulse(
      input realtime start_delay,
      input real assert_time,
      input realtime gap_time,
      input int  pulse_count
   );

      int i;
      string str;

      if (start_delay > 0)
         #(start_delay);

      for (i = 0; i < pulse_count; i++) begin

         // ASSERT RESET
         uvm_report_info("RST_IF/INFO" , $sformatf("asserting reset for %1t", assert_time), UVM_HIGH);
         rst_n = 1'b0;
         #(assert_time);

         // DEASSERT RESET
         str = gap_time > 0 ? $sformatf("releasing reset for %1t",gap_time) : "releasing reset until next reset item";
         uvm_report_info("RST_IF/INFO" , str, UVM_HIGH);  
         rst_n = 1'b1;

         if (i < pulse_count - 1)
            #(gap_time);

         uvm_report_info("RST_IF/INFO" ,$sformatf("finished reset pulse %0d",(i+1)), UVM_HIGH);
      end

   endtask


endinterface