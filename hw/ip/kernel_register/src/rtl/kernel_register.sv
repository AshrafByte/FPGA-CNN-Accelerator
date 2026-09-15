//------------------------------------------------------------------------------
// Module: kernel_register
//
// Description:
//   Holds the WINDOW_SIZE**2 signed kernel weights, loaded serially.
//
// Architecture:
//   - Weights shift in: each write moves every stored weight down one index
//     and places the new weight at the top, so after WINDOW_ELEMENTS writes
//     the first weight written sits at index 0 - the same final placement as
//     an indexed write, without a write pointer or a per-register address
//     decode (the indexed version spent 16 LUTs on that decode).
//   - The shift is a register chain with a clock enable. The asynchronous
//     reset keeps it out of SRLs, which would cost LUTs.
//   - o_ready rises once exactly WINDOW_ELEMENTS weights have been loaded.
//     A write while o_ready is high starts a new load: the count restarts at
//     one, so a full reload of WINDOW_ELEMENTS weights raises o_ready again
//     without a reset, and an over-long load leaves it low - visible rather
//     than silently accepted.
//
// Timing:
//   - Zero additional latency: o_weights reads the registers directly.
//
// Assumptions:
//   - The kernel is loaded before a frame streams and stays constant during
//     it; it may be reloaded between frames.
//
// Parameters:
//   PIXEL_WIDTH : Width of each weight.
//   WINDOW_SIZE : Kernel dimension.
//------------------------------------------------------------------------------
module kernel_register
   #(
      parameter int PIXEL_WIDTH = 8,
      parameter int WINDOW_SIZE = 3,

      localparam int  WINDOW_ELEMENTS = WINDOW_SIZE ** 2,
      localparam type pixel_t         = logic signed [PIXEL_WIDTH-1:0]
   )(
      input logic clk,
      input logic rst_n,

      input logic   i_write_en,
      input pixel_t i_weight,

      output pixel_t o_weights[WINDOW_ELEMENTS],
      output logic   o_ready
   );

   localparam type load_cnt_t = logic [$clog2(WINDOW_ELEMENTS+1)-1:0];

   pixel_t    r_weights    [WINDOW_ELEMENTS];
   load_cnt_t r_loaded_cnt;

   always_ff @(posedge clk or negedge rst_n) begin: kernel_registers
      if (!rst_n) begin
         r_weights    <= '{default: '0};
         r_loaded_cnt <= '0;
      end else if (i_write_en) begin
         for (int k = 0; k < WINDOW_ELEMENTS-1; k++)
            r_weights[k] <= r_weights[k+1];
         r_weights[WINDOW_ELEMENTS-1] <= i_weight;

         if (r_loaded_cnt < load_cnt_t'(WINDOW_ELEMENTS))
            r_loaded_cnt <= r_loaded_cnt + 1'b1;
         else
            r_loaded_cnt <= load_cnt_t'(1);   // this write is the first of a new load
      end
   end: kernel_registers

   assign o_weights = r_weights;
   assign o_ready   = (r_loaded_cnt == load_cnt_t'(WINDOW_ELEMENTS));

endmodule
