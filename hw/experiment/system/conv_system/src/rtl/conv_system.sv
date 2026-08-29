//------------------------------------------------------------------------------
// Module: conv_system
//
// Description:
//   Top-level integration of a streaming 2D convolution pipeline: pixel
//   acceptance gating, line buffer, window generator, kernel register,
//   multiplier array, adder tree, and an output FIFO, wired end to end to
//   produce a smoothed, gap-absorbed output feature stream.
//
// Architecture:
//   - This module has NO knowledge of external memory, addressing, or
//     where i_pixel comes from — it only reacts to i_pixel/i_valid_in as
//     presented, cycle by cycle. Any caller-side memory (BRAM, a sensor
//     interface, a testbench array) is entirely the caller's concern;
//     conv_system exposes no address port because it has nothing to
//     address.
//   - Pixel acceptance (w_write_en) is a one-cycle-delayed registered
//     mirror of i_valid_in, matching the latency convention every other
//     stage uses.
//   - line_buffer stores only the WINDOW_SIZE-1 rows preceding the row
//     currently streaming in — the current row is consumed live, directly
//     off i_pixel, by window_generator.
//   - kernel_register holds statically-loaded kernel weights.
//   - multiplier_array + adder_tree compute the windowed multiply-accumulate.
//   - output_fifo absorbs the row-boundary valid gaps inherent to
//     adder_tree's output, re-emitting a prefill-gated, continuously
//     draining feature stream.
//
// Data Flow:
//   - i_pixel streams in under w_write_en, consumed by line_buffer (history)
//     and window_generator (live current-row tap) simultaneously.
//   - i_weights load into kernel_register via i_load_en.
//   - adder_tree's gapped valid+sum feeds output_fifo, which buffers and
//     smooths the stream before driving o_feature/o_valid_out.
//
// Timing:
//   - w_write_en is a registered, one-cycle-delayed copy of i_valid_in.
//   - o_valid_out naturally returns low once i_valid_in has been low long
//     enough for every real pipeline stage (including output_fifo) to
//     drain — no explicit "frame done" signal is needed anywhere in this
//     chain, since every stage's valid/enable ultimately derives from
//     i_valid_in's own level.
//
// Assumptions:
//   - Caller is solely responsible for presenting i_pixel/i_valid_in in the
//     correct raster order for a WINDOW_SIZE x WINDOW_SIZE convolution over
//     an INPUT_SIZE x INPUT_SIZE image — this module does not generate,
//     track, or validate any addressing on the caller's behalf.
//   - i_load_en (kernel load) completes before i_valid_in first starts a
//     streaming pass; no support for changing weights mid-frame.
//   - All sub-modules share the same clk/rst_n domain.
//   - output_fifo's internal prefill latch is reset only by the global
//     rst_n, not per-frame — this design does not yet support processing a
//     second frame back-to-back without an external reset between frames.
//
// Parameters:
//   PIXEL_WIDTH : Width of each input pixel and kernel weight.
//   WINDOW_SIZE : Kernel dimension (e.g. 3 for a 3x3 kernel).
//   INPUT_SIZE  : Image row width.
//   MEMORY_SIZE : Total number of elements in one frame (used only to size
//                 output_fifo's gap-bridging depth, not for addressing).
//------------------------------------------------------------------------------
module conv_system #(
   parameter int PIXEL_WIDTH = 8,
   parameter int WINDOW_SIZE = 3,
   parameter int INPUT_SIZE  = 32,
   parameter int MEMORY_SIZE = INPUT_SIZE ** 2,

   localparam int  WINDOW_ELEMENTS = WINDOW_SIZE ** 2,
   localparam int  PRODUCT_WIDTH   = 2 * PIXEL_WIDTH,
   localparam int  FEATURE_WIDTH   = PRODUCT_WIDTH + $clog2(WINDOW_ELEMENTS),
   localparam type pixel_t         = logic [PIXEL_WIDTH-1:0],
   localparam type feature_t       = logic [FEATURE_WIDTH-1:0],

   localparam int FIFO_DEPTH             = (INPUT_SIZE - WINDOW_SIZE) * (WINDOW_SIZE - 1),
   localparam int FIFO_PREFILL_THRESHOLD = FIFO_DEPTH
)(
   input  logic  clk,
   input  logic  rst_n,

   input  logic   i_valid_in,
   input  pixel_t i_pixel,
   input  logic   i_load_en,
   input  pixel_t i_weights[WINDOW_ELEMENTS],

   output feature_t o_feature,
   output logic     o_valid_out
);

   localparam int LINE_NUM = WINDOW_SIZE;

   logic     w_write_en;
   logic     w_row_done;
   logic     w_rows_ready;
   logic     w_window_valid;
   logic     w_mult_valid;
   logic     w_sum_valid;
   pixel_t   w_rows   [LINE_NUM-1];
   pixel_t   w_window [WINDOW_ELEMENTS];
   pixel_t   w_weights[WINDOW_ELEMENTS];
   feature_t w_feature;
   logic [PRODUCT_WIDTH-1:0] w_products[WINDOW_ELEMENTS];


   always_ff @(posedge clk or negedge rst_n) begin: write_en_register
      if (!rst_n) w_write_en <= 1'b0;
      else        w_write_en <= i_valid_in;
   end: write_en_register

   line_buffer #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .LINE_LENGTH(INPUT_SIZE),
      .LINE_NUM   (LINE_NUM)
   ) u_line_buffer (
      .clk         (clk),
      .rst_n       (rst_n),
      .i_write_en  (w_write_en),
      .i_pixel     (i_pixel),
      .o_rows      (w_rows),
      .o_row_done  (w_row_done),
      .o_rows_ready(w_rows_ready)
   );

   window_generator #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .WINDOW_SIZE(WINDOW_SIZE)
   ) u_window_generator (
      .clk         (clk),
      .rst_n       (rst_n),
      .i_write_en  (w_write_en),
      .i_row_done  (w_row_done),
      .i_rows_ready(w_rows_ready),
      .i_rows      (w_rows),
      .i_pixel     (i_pixel),
      .o_window    (w_window),
      .o_valid_out (w_window_valid)
   );

   kernel_register #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .WINDOW_SIZE(WINDOW_SIZE)
   ) u_kernel_register (
      .clk        (clk),
      .rst_n      (rst_n),
      .i_load_en  (i_load_en),
      .i_load_data(i_weights),
      .o_weights  (w_weights)
   );

   multiplier_array #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .INPUTS_NUM (WINDOW_ELEMENTS)
   ) u_multiplier_array (
      .clk        (clk),
      .rst_n      (rst_n),
      .i_valid_in (w_window_valid),
      .i_pixels   (w_window),
      .i_weights  (w_weights),
      .o_products (w_products),
      .o_valid_out(w_mult_valid)
   );

   adder_tree #(
      .PRODUCT_WIDTH(PRODUCT_WIDTH),
      .NUM_INPUTS   (WINDOW_ELEMENTS)
   ) u_adder_tree (
      .clk        (clk),
      .rst_n      (rst_n),
      .i_valid_in (w_mult_valid),
      .i_products (w_products),
      .o_sum      (w_feature),
      .o_valid_out(w_sum_valid)
   );

   output_fifo #(
      .PIXEL_WIDTH      (FEATURE_WIDTH),
      .DEPTH            (FIFO_DEPTH),
      .PREFILL_THRESHOLD(FIFO_PREFILL_THRESHOLD)
   ) u_output_fifo (
      .clk        (clk),
      .rst_n      (rst_n),
      .i_valid_in (w_sum_valid),
      .i_data_in  (w_feature),
      .o_data_out (o_feature),
      .o_valid_out(o_valid_out)
   );

endmodule