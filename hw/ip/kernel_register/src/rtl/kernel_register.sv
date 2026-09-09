//------------------------------------------------------------------------------
// Module: kernel_register
//
// Description:
//   Serially-loaded register bank holding a flattened WINDOW_SIZE x
//   WINDOW_SIZE set of kernel weights. Unlike a parallel-array load port
//   (which would need WINDOW_SIZE**2 * PIXEL_WIDTH bits arriving in one
//   cycle, or PIXEL_WIDTH bits x WINDOW_SIZE**2 wires held for a whole
//   column), this module accepts ONE weight value per cycle over a single
//   PIXEL_WIDTH-wide bus, tracking its own write pointer. This is what lets
//   the top-level system share a single data bus between pixels and
//   weights (see conv_system) instead of paying for two separate I/O buses.
//
// Architecture:
//   - Flat array of WINDOW_SIZE**2 registers, filled one element per cycle
//     at an internally-tracked write pointer that wraps after a full load.
//   - o_ready is a sticky level: once WINDOW_SIZE**2 weights have been
//     loaded, it stays high until reset, regardless of further loads
//     (a caller reloading weights mid-operation will simply overwrite
//     from index 0 again, without o_ready ever dropping).
//
// Data Flow:
//   - i_weight is captured into r_weights[r_wr_ptr] whenever i_valid is
//     asserted; the pointer advances (and wraps) on the same cycle.
//   - o_weights continuously reflects the full, currently-loaded set.
//
// Timing:
//   - Load and pointer advance occur synchronously on the rising clock
//     edge when i_valid is high.
//   - o_weights is a direct combinational read of the registered weights
//     (zero additional latency).
//
// Assumptions:
//   - Caller presents exactly WINDOW_SIZE**2 consecutive i_valid cycles
//     to fully load one kernel, in the intended tap order (index 0 first).
//     Asserting i_valid for more or fewer cycles than WINDOW_SIZE**2
//     either wraps back to index 0 (more) or leaves some taps at their
//     prior value (fewer) — this module does not detect either condition.
//   - Caller does not assert i_valid concurrently with pixel streaming
//     if changing weights mid-frame is not intended (see conv_system's
//     own assumptions about the shared pixel/weight bus).
//
// Parameters:
//   PIXEL_WIDTH : Bit width of each weight value.
//   WINDOW_SIZE : Kernel dimension; total weights loaded = WINDOW_SIZE**2.
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

   localparam type idx_t      = logic [$clog2(WINDOW_ELEMENTS)-1:0];
   localparam type load_cnt_t = logic [$clog2(WINDOW_ELEMENTS+1)-1:0];

   pixel_t    r_weights    [WINDOW_ELEMENTS];
   idx_t      r_wr_ptr;
   load_cnt_t r_loaded_cnt;

   always_ff @(posedge clk or negedge rst_n) begin: kernel_registers
      if (!rst_n) begin : reset_kernel_registers
         r_weights    <= '{default: '0};
         r_wr_ptr     <= '0;
         r_loaded_cnt <= '0;
      end else if (i_write_en) begin : load_kernel_registers
         r_weights[r_wr_ptr] <= i_weight;
         r_wr_ptr            <= (r_wr_ptr == idx_t'(WINDOW_ELEMENTS-1)) ? '0 : r_wr_ptr + 1'b1;
         if (r_loaded_cnt < load_cnt_t'(WINDOW_ELEMENTS))
            r_loaded_cnt <= r_loaded_cnt + 1'b1;
      end
   end: kernel_registers

   assign o_weights = r_weights;
   assign o_ready   = (r_loaded_cnt == load_cnt_t'(WINDOW_ELEMENTS));

endmodule