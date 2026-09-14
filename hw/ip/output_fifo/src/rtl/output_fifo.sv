//------------------------------------------------------------------------------
// Module: output_fifo
//
// Description:
//   Prefill-gated FIFO that turns the gapped feature stream into a continuous
//   one: once PREFILL_THRESHOLD entries have accumulated it drains one entry
//   per cycle until empty.
//
// Architecture:
//   - Memory of RAM_DEPTH = 2^$clog2(DEPTH+1) entries, a power of two strictly
//     greater than DEPTH. The pointers are exactly $clog2(RAM_DEPTH) bits wide
//     and wrap on their own, so there is no wrap comparator.
//   - There is no occupancy counter. Occupancy never exceeds DEPTH, which is
//     below RAM_DEPTH, so the FIFO is empty exactly when the two pointers are
//     equal. That equality replaces the up/down counter and its != 0 test.
//   - Prefill: before the first read the read pointer is still 0, so
//     occupancy equals the write pointer and the threshold test can look at
//     the write pointer alone. The latch is sticky.
//   - USE_BRAM selects the memory primitive (chosen by conv_system from the
//     figure-of-merit cost of each):
//       0: distributed RAM (LUTRAM). o_data is a reset register after an
//          asynchronous read.
//       1: block RAM. The read is synchronous and its register is the BRAM
//          output register, so it carries no reset. Same cycle timing as the
//          LUTRAM version: o_data updates on the cycle o_valid rises.
//     A read never targets the address being written (reads only happen when
//     the pointers differ), so read/write collision behaviour does not matter.
//
// Timing:
//   - o_data/o_valid are registered; o_data holds between valids and is only
//     meaningful while o_valid is high (in the BRAM version it is undefined
//     until the first read).
//
// Assumptions:
//   - Caller sizes DEPTH >= the peak occupancy (conv_system does).
//   - The prefill latch clears only on rst_n.
//
// Parameters:
//   PIXEL_WIDTH      : Width of each stored element.
//   DEPTH            : Peak occupancy the caller needs.
//   PREFILL_THRESHOLD: Occupancy that must be reached once before draining.
//   USE_BRAM         : 1 = block RAM, 0 = distributed RAM.
//------------------------------------------------------------------------------
module output_fifo
   #(
      parameter int PIXEL_WIDTH       = 8,
      parameter int DEPTH             = 64,
      parameter int PREFILL_THRESHOLD = DEPTH,
      parameter bit USE_BRAM          = 1'b0,

      localparam int  ADDR_WIDTH = $clog2(DEPTH + 1),
      localparam int  RAM_DEPTH  = 1 << ADDR_WIDTH,
      localparam type pixel_t    = logic signed [PIXEL_WIDTH-1:0],
      localparam type addr_t     = logic [ADDR_WIDTH-1:0]
   )(
      input logic clk,
      input logic rst_n,

      input logic   i_valid,
      input pixel_t i_data,

      output pixel_t o_data,
      output logic   o_valid
   );

   addr_t q_write_ptr;
   addr_t q_read_ptr;
   logic  q_prefilled;

   logic  w_will_read;

   assign w_will_read = q_prefilled && (q_read_ptr != q_write_ptr);

   always_ff @(posedge clk or negedge rst_n) begin: pointer_registers
      if (!rst_n) begin
         q_write_ptr <= '0;
         q_read_ptr  <= '0;
         q_prefilled <= 1'b0;
      end else begin
         if (i_valid)     q_write_ptr <= q_write_ptr + 1'b1;
         if (w_will_read) q_read_ptr  <= q_read_ptr  + 1'b1;
         if (q_write_ptr >= addr_t'(PREFILL_THRESHOLD-1))
            q_prefilled <= 1'b1;
      end
   end: pointer_registers

   generate
      if (USE_BRAM) begin : gen_bram

         (* ram_style = "block" *)
         pixel_t r_mem [RAM_DEPTH];
         pixel_t r_rd_data;

         // Synchronous write and synchronous, enabled read: the BRAM pattern.
         always_ff @(posedge clk) begin: fifo_memory
            if (i_valid)
               r_mem[q_write_ptr] <= i_data;
            if (w_will_read)
               r_rd_data <= r_mem[q_read_ptr];
         end: fifo_memory

         assign o_data = r_rd_data;
      end : gen_bram

      else begin : gen_lutram

         (* ram_style = "distributed" *)
         pixel_t r_mem [RAM_DEPTH];

         always_ff @(posedge clk) begin: fifo_memory
            if (i_valid)
               r_mem[q_write_ptr] <= i_data;
         end: fifo_memory

         always_ff @(posedge clk or negedge rst_n) begin: output_data
            if (!rst_n)
               o_data <= '0;
            else if (w_will_read)
               o_data <= r_mem[q_read_ptr];
         end: output_data
      end : gen_lutram
   endgenerate

   always_ff @(posedge clk or negedge rst_n) begin: output_valid
      if (!rst_n)
         o_valid <= 1'b0;
      else
         o_valid <= w_will_read;
   end: output_valid

endmodule
