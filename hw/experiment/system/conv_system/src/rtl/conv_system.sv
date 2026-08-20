//------------------------------------------------------------------------------
// Module: conv_system
//
// Description:
//   Top-level integration of a streaming 2D convolution pipeline: controller,
//   line buffer, window generator, kernel register, multiplier array, and
//   adder tree, wired end to end for one output feature per valid window.
//
// Architecture:
//   - conv_controller drives BRAM-style read addressing and write-enable.
//   - line_buffer + window_generator produce a validated sliding window.
//   - kernel_register holds statically-loaded kernel weights.
//   - multiplier_array + adder_tree compute the windowed multiply-accumulate.
//   - Valid is propagated stage to stage (line_buffer -> window_generator ->
//     multiplier_array -> adder_tree) rather than tracked via a fixed
//     top-level pipeline-latency parameter.
//
// Data Flow:
//   - i_pixel streams in under conv_controller's addressing/write-enable.
//   - i_weights load into kernel_register via i_load_en.
//   - Each pipeline stage consumes the previous stage's valid+data and
//     produces its own delayed valid+data pair.
//   - o_feature/o_valid_out reflect the final accumulated convolution result.
//
// Timing:
//   - Total system latency is an emergent property of the chained valid
//     signals, not a manually maintained constant.
//   - o_valid_out may deassert briefly at row boundaries (structural to
//     valid/unpadded convolution) — downstream consumers must be valid-gated.
//
// Assumptions:
//   - i_load_en (kernel load) completes before i_valid_in first starts a
//     streaming pass; no support for changing weights mid-frame.
//   - All sub-modules share the same clk/rst_n domain.
//   - Downstream consumer of o_feature only acts on cycles where o_valid_out
//     is high.
//
// Parameters:
//   PIXEL_WIDTH : Width of each input pixel and kernel weight.
//   WINDOW_SIZE : Kernel dimension (e.g. 3 for a 3x3 kernel).
//   INPUT_SIZE  : Image row width.
//   MEMORY_SIZE : Total number of addressable elements in the frame.
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
   localparam type addr_t          = logic [$clog2(MEMORY_SIZE)-1:0],
   localparam type feature_t       = logic [FEATURE_WIDTH-1:0]
)(
   input  logic  clk,
   input  logic  rst_n,

   input  logic   i_valid_in,
   input  pixel_t i_pixel,
   input  logic   i_load_en,
   input  pixel_t i_weights[WINDOW_ELEMENTS],

   output addr_t    o_raddr,
   output feature_t o_feature,
   output logic     o_valid_out
);

   localparam int LINE_NUM = WINDOW_SIZE;

   logic   w_write_en;
   logic   w_row_done;
   logic   w_rows_ready;
   logic   w_window_valid;
   logic   w_mult_valid;
   pixel_t w_rows   [LINE_NUM];
   pixel_t w_window [WINDOW_ELEMENTS];
   pixel_t w_weights[WINDOW_ELEMENTS];
   logic [PRODUCT_WIDTH-1:0] w_products[WINDOW_ELEMENTS];

   conv_controller #(
      .LINE_NUM   (LINE_NUM),
      .INPUT_SIZE (INPUT_SIZE),
      .MEMORY_SIZE(MEMORY_SIZE)
   ) u_conv_controller (
      .clk       (clk),
      .rst_n     (rst_n),
      .i_valid_in(i_valid_in),
      .o_raddr   (o_raddr),
      .o_write_en(w_write_en)
   );

   line_buffer #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .LINE_LENGTH(INPUT_SIZE),
      .LINE_NUM   (LINE_NUM)
   ) u_line_buffer (
      .clk        (clk),
      .rst_n      (rst_n),
      .i_write_en (w_write_en),
      .i_pixel    (i_pixel),
      .o_rows     (w_rows),
      .o_row_done (w_row_done),
      .o_rows_ready(w_rows_ready)
   );

   window_generator #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .WINDOW_SIZE(WINDOW_SIZE)
   ) u_window_generator (
      .clk        (clk),
      .rst_n      (rst_n),
      .i_shift_en (w_write_en),
      .i_row_done (w_row_done),
      .i_rows_ready(w_rows_ready),
      .i_rows     (w_rows),
      .o_window   (w_window),
      .o_valid_out(w_window_valid)
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
      .o_sum      (o_feature),
      .o_valid_out(o_valid_out)
   );

endmodule