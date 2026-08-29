//------------------------------------------------------------------------------
// Module: output_fifo
//
// Description:
//   Synchronous elastic buffer that absorbs gaps in an upstream valid signal
//   and re-emits a smoothed, continuously-draining output stream. Buffers
//   elements while upstream provides them and drains one element per cycle
//   whenever any data is available, decoupling downstream timing from
//   upstream burstiness (e.g. row-boundary gaps in a streaming pipeline).
//
// Architecture:
//   - Standard circular-buffer FIFO: independent read/write pointers plus
//     an explicit occupancy counter.
//   - Prefill gate: draining does not begin until occupancy has reached
//     PREFILL_THRESHOLD at least once, guaranteeing enough cushion is
//     banked before the output stream starts relying on it. Once reached,
//     draining continues for as long as any data remains buffered.
//   - No backpressure/ready signal — draining, once primed, is automatic
//     and unconditional whenever the FIFO is non-empty.
//
// Data Flow:
//   - i_data_in is written whenever i_valid_in is high.
//   - No output is produced until occupancy first reaches PREFILL_THRESHOLD.
//   - After that point, o_data_out reflects the oldest buffered element,
//     advancing and asserting o_valid_out on every cycle the FIFO holds
//     at least one element.
//
// Timing:
//   - Read and write pointers, occupancy count, prefill state, and data
//     memory are all updated on the rising clock edge.
//   - o_data_out/o_valid_out are registered, one cycle after the
//     corresponding read decision.
//   - Prefill trigger fires one count EARLY (>= PREFILL_THRESHOLD-1, not
//     PREFILL_THRESHOLD): since q_prefilled itself is registered and lags
//     q_count by one cycle, comparing against the exact threshold would let
//     occupancy reach PREFILL_THRESHOLD (i.e. completely full when
//     PREFILL_THRESHOLD == DEPTH) for one cycle before draining begins,
//     during which a write would silently overwrite address 0 before it was
//     ever read. Triggering one count early ensures draining is already
//     active by the cycle occupancy would otherwise overflow.
//
// Assumptions:
//   - Caller sizes DEPTH and PREFILL_THRESHOLD together, derived from the
//     actual upstream gap pattern and total frame length at the integration
//     site, such that the buffered cushion never runs out before the last
//     element of the frame has been written. This module does not detect
//     or guard against underflow/overflow if that assumption is wrong.
//   - i_valid_in reflects that i_data_in is valid and stable on the same cycle.
//   - The prefill latch is sticky and only clears on rst_n — this module
//     does not yet support resetting prefill state between frames without
//     an external reset pulse (see conv_system's assumptions).
//
// Parameters:
//   PIXEL_WIDTH      : Width of each buffered element.
//   DEPTH            : Number of elements the FIFO can hold; sized by the caller.
//   PREFILL_THRESHOLD: Occupancy level that must be reached once before
//                      draining begins; sized by the caller to survive the
//                      worst-case upstream gap.
//------------------------------------------------------------------------------
module output_fifo
   #(
      parameter int PIXEL_WIDTH       = 8,
      parameter int DEPTH             = 64,
      parameter int PREFILL_THRESHOLD = DEPTH,

      localparam type pixel_t = logic [PIXEL_WIDTH-1:0]
   )(
      input logic clk,
      input logic rst_n,

      input logic   i_valid_in,
      input pixel_t i_data_in,

      output pixel_t o_data_out,
      output logic   o_valid_out
   );

   localparam type addr_t  = logic [$clog2(DEPTH)-1:0];
   localparam type count_t = logic [$clog2(DEPTH+1)-1:0];

   pixel_t r_mem [DEPTH];

   addr_t  q_write_ptr, d_write_ptr;
   addr_t  q_read_ptr, d_read_ptr;
   count_t q_count, d_count;
   logic   q_prefilled, d_prefilled;

   logic w_will_write;
   logic w_will_read;

   assign w_will_write = i_valid_in;
   assign w_will_read  = q_prefilled && (q_count != '0);

   assign d_write_ptr = w_will_write ? ((q_write_ptr == addr_t'(DEPTH-1)) ? '0 : q_write_ptr + 1'b1) : q_write_ptr;
   assign d_read_ptr  = w_will_read  ? ((q_read_ptr  == addr_t'(DEPTH-1)) ? '0 : q_read_ptr  + 1'b1) : q_read_ptr;

   always_ff @(posedge clk or negedge rst_n) begin: pointer_registers
      if (!rst_n) begin
         q_write_ptr <= '0;
         q_read_ptr  <= '0;
         q_count     <= '0;
         q_prefilled <= 1'b0;
      end else begin
         q_write_ptr <= d_write_ptr;
         q_read_ptr  <= d_read_ptr;
         q_count     <= d_count;
         q_prefilled <= d_prefilled;
      end
   end: pointer_registers

   always_comb begin: occupancy_next
      d_count = q_count;
      if (w_will_write && !w_will_read)
         d_count = q_count + 1'b1;
      else if (!w_will_write && w_will_read)
         d_count = q_count - 1'b1;
      else
         d_count = q_count;
   end: occupancy_next

   // sticky: once reached, stays primed for the rest of the frame.
   // Triggers one count early - see Timing note above for why.
   assign d_prefilled = q_prefilled || (q_count >= count_t'(PREFILL_THRESHOLD-1));

   always_ff @(posedge clk) begin: fifo_memory
      if (w_will_write)
         r_mem[q_write_ptr] <= i_data_in;
   end: fifo_memory

   always_ff @(posedge clk or negedge rst_n) begin: output_register
      if (!rst_n) begin
         o_data_out  <= '0;
         o_valid_out <= 1'b0;
      end else begin
         o_valid_out <= w_will_read;
         if (w_will_read)
            o_data_out <= r_mem[q_read_ptr];
      end
   end: output_register

endmodule