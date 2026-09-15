//------------------------------------------------------------------------------
// Module: output_fifo
//
// Description:
//   Prefill-gated FIFO that turns the gapped feature stream into a continuous
//   one: once PREFILL_THRESHOLD entries have accumulated it drains one entry
//   per cycle until empty. i_last marks the last entry of a frame; reading
//   that entry raises o_last with it and re-arms the prefill, so every frame
//   is buffered the same way without a reset.
//
// Architecture:
//   - Memory of RAM_DEPTH = 2^$clog2(DEPTH+1) entries, a power of two strictly
//     greater than DEPTH. The pointers are exactly $clog2(RAM_DEPTH) bits wide
//     and wrap on their own, so there is no wrap comparator.
//   - There is no occupancy counter. Occupancy never exceeds DEPTH, which is
//     below RAM_DEPTH, so the FIFO is empty exactly when the two pointers are
//     equal. That equality replaces the up/down counter and its != 0 test.
//   - Prefill: while the latch is clear no read has happened since the
//     pointers were last zeroed, so occupancy equals the write pointer and the
//     threshold test can look at the write pointer alone.
//   - Frames: q_last_written records that the frame's last entry has been
//     written. The FIFO is next empty on the cycle o_valid presents that
//     entry; that condition is o_last, and on the following edge it clears
//     the prefill latch and returns both pointers to zero, which restores the
//     prefill invariant for the next frame. The pointers and flags use a
//     synchronous clear shared by rst_n and the frame end, so the frame logic
//     costs no LUTs in the pointer next-state logic. With i_last tied low the
//     latch is sticky until rst_n and the frame logic is removed.
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
//     until the first read). o_last is a decode of three registers, high only
//     together with o_valid, on the frame's last entry.
//   - rst_n clears the pointers and flags synchronously (the clock runs during
//     reset); o_valid and o_data keep their asynchronous reset.
//
// Assumptions:
//   - Caller sizes DEPTH >= the peak occupancy (conv_system does).
//   - The next frame's first entry is written only after the previous frame's
//     last entry has been read. conv_system guarantees it: a frame needs
//     (N-1)(W+1)+1 accepted pixels before its first feature, more than the
//     DEPTH = (W-N)(N-1) entries left to drain. A simulation check reports a
//     violation.
//
// Parameters:
//   PIXEL_WIDTH      : Width of each stored element.
//   DEPTH            : Peak occupancy the caller needs.
//   PREFILL_THRESHOLD: Occupancy that must be reached before a frame drains.
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
      input logic   i_last,

      output pixel_t o_data,
      output logic   o_valid,
      output logic   o_last
   );

   addr_t q_write_ptr;
   addr_t q_read_ptr;
   logic  q_prefilled;
   logic  q_last_written;

   logic  q_clear;
   logic  w_empty;
   logic  w_will_read;
   logic  w_frame_end;

   assign w_empty     = (q_read_ptr == q_write_ptr);
   assign w_will_read = q_prefilled && !w_empty;
   // Once the frame's last entry has been written the FIFO is not empty again
   // until that entry has been read, so "prefilled, last written and empty"
   // is true exactly on the cycle o_valid presents the last entry. It reuses
   // the empty comparator and needs no pointer arithmetic. The flags are only
   // cleared one cycle later (q_clear), so !q_clear keeps it to one cycle.
   assign w_frame_end = q_prefilled && q_last_written && w_empty && !q_clear;

   // The clear is registered: the comparator then drives one flip-flop, not
   // the reset pins of every pointer bit. Delaying it a cycle is safe because
   // the FIFO stays empty and the next frame's first entry is still at least
   // (N-1)(W+1) cycles away.
   always_ff @(posedge clk) begin: clear_register
      if (!rst_n) q_clear <= 1'b0;
      else        q_clear <= w_frame_end;
   end: clear_register

   // Synchronous clear: rst_n and the frame end share the flip-flops' reset
   // pin instead of adding a term to every pointer bit's next-state logic.
   always_ff @(posedge clk) begin: pointer_registers
      if (!rst_n || q_clear) begin
         q_write_ptr    <= '0;
         q_read_ptr     <= '0;
         q_prefilled    <= 1'b0;
         q_last_written <= 1'b0;
      end else begin
         if (i_valid)     q_write_ptr <= q_write_ptr + 1'b1;
         if (w_will_read) q_read_ptr  <= q_read_ptr  + 1'b1;
         if (q_write_ptr >= addr_t'(PREFILL_THRESHOLD-1))
            q_prefilled <= 1'b1;
         if (i_valid && i_last)
            q_last_written <= 1'b1;
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

   assign o_last = w_frame_end;

   // synthesis translate_off
   always @(posedge clk)
      if (rst_n && (w_frame_end || q_clear) && i_valid)
         $error("[output_fifo] next frame's first entry arrived before the last one drained");
   // synthesis translate_on

endmodule
