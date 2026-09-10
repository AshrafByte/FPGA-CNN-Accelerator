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
//   - Pixel acceptance (w_pixel_write_en) is a one-cycle-delayed registered
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
//   - i_pixel streams in under w_pixel_write_en, consumed by line_buffer (history)
//     and window_generator (live current-row tap) simultaneously.
//   - i_weights load into kernel_register via i_load_en.
//   - adder_tree's gapped valid+sum feeds output_fifo, which buffers and
//     smooths the stream before driving o_feature/o_valid_out.
//
// Timing:
//   - w_pixel_write_en is a registered, one-cycle-delayed copy of i_valid_in.
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
module conv_system
   #(
      parameter int PIXEL_WIDTH = 8,
      parameter int WINDOW_SIZE = 3,
      parameter int INPUT_SIZE  = 32,
      parameter int FEATURE_WIDTH= 16,
      parameter int NUM_KERNELS = 1,

      localparam int  WINDOW_ELEMENTS = WINDOW_SIZE ** 2,
      localparam int  PRODUCT_WIDTH   = 2 * PIXEL_WIDTH,
      localparam int  ACCUM_WIDTH     = PRODUCT_WIDTH + $clog2(WINDOW_ELEMENTS),
      localparam type data_t          = logic [PIXEL_WIDTH-1:0],
      localparam type accum_t         = logic signed [ACCUM_WIDTH-1:0],
      localparam type feature_t       = logic signed [FEATURE_WIDTH-1:0],
      localparam type sel_ker_t       = logic [$clog2(NUM_KERNELS):0]
   )(
      input logic clk,
      input logic rst_n,

      input data_t i_data,
      input logic  i_pixel_valid,
      input logic  i_weight_valid,
      input sel_ker_t i_select_kernel,

      output feature_t o_feature [NUM_KERNELS],
      output logic     o_valid 
   );

   localparam int  LINE_NUM  = WINDOW_SIZE;
   localparam type k_data_t  = logic signed [PIXEL_WIDTH-1:0];
   localparam type product_t = logic signed [PRODUCT_WIDTH-1:0];
   localparam int FIFO_DEPTH             = (INPUT_SIZE - WINDOW_SIZE) * (WINDOW_SIZE - 1);
   localparam int FIFO_PREFILL_THRESHOLD = FIFO_DEPTH;

   logic r_pixel_write_en;
   logic r_weight_write_en;
   logic w_row_done;
   logic w_rows_ready;
   logic w_window_valid;
   logic w_products_valid [NUM_KERNELS];
   logic w_accum_valid [NUM_KERNELS];
   logic w_feature_valid [NUM_KERNELS];
   logic w_operands_valid;
   logic [NUM_KERNELS-1:0] w_kernel_ready ;
   logic w_all_kernels_ready;
   logic w_o_valid [NUM_KERNELS];


   data_t w_rows   [LINE_NUM];
   data_t w_window [WINDOW_ELEMENTS];

   k_data_t w_weights [NUM_KERNELS][WINDOW_ELEMENTS];

   accum_t w_accum [NUM_KERNELS];
   feature_t w_feature [NUM_KERNELS];
   product_t w_products [NUM_KERNELS][WINDOW_ELEMENTS];
   data_t r_data;

   genvar i ;

   assign w_all_kernels_ready = &w_kernel_ready;
   assign w_operands_valid = w_all_kernels_ready && w_window_valid;
   assign o_valid = w_o_valid[0] ;

   always_ff @(posedge clk or negedge rst_n) begin: write_en_register
      if (!rst_n) begin
         r_weight_write_en <= 1'b0;
         r_pixel_write_en  <= 1'b0;
         r_data <= '0;
      end else begin
         r_pixel_write_en  <= i_pixel_valid;
         r_weight_write_en <= i_weight_valid;
         r_data <= i_data;
      end
   end: write_en_register

   line_buffer #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .LINE_LENGTH(INPUT_SIZE),
      .LINE_NUM (LINE_NUM)
   ) u_line_buffer (
      .clk (clk),
      .rst_n (rst_n),

      .i_write_en (r_pixel_write_en),
      .i_pixel (r_data),
      
      .o_rows (w_rows),
      .o_row_done (w_row_done),
      .o_rows_ready(w_rows_ready)
   );

   window_generator #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .WINDOW_SIZE(WINDOW_SIZE)
   ) u_window_generator (
      .clk (clk),
      .rst_n (rst_n),

      .i_write_en (r_pixel_write_en),
      .i_row_done (w_row_done),
      .i_rows_ready(w_rows_ready),
      .i_rows (w_rows),

      .o_window (w_window),
      .o_valid (w_window_valid)
   );
   
   generate
      for(i=0;i<NUM_KERNELS;i++) begin
         logic w_kernel_en[NUM_KERNELS] ;
         assign w_kernel_en[i] = r_weight_write_en&&(i_select_kernel==i);

         kernel_register #(
            .PIXEL_WIDTH(PIXEL_WIDTH),
            .WINDOW_SIZE(WINDOW_SIZE)
         ) u_kernel_register (
            .clk (clk),
            .rst_n (rst_n),
            
            .i_write_en (w_kernel_en[i]),
            .i_weight(r_data),

            .o_weights (w_weights[i]),
            .o_ready(w_kernel_ready[i])
         );
      end
   endgenerate

   generate
      for(i=0;i<NUM_KERNELS;i++) begin
         multiplier_array #(
            .PIXEL_WIDTH(PIXEL_WIDTH),
            .INPUTS_NUM (WINDOW_ELEMENTS)
         ) u_multiplier_array (
            .clk (clk),
            .rst_n (rst_n),
            
            .i_valid (w_operands_valid),
            .i_pixels (w_window),
            .i_weights (w_weights[i]),

            .o_products (w_products[i]),
            .o_valid(w_products_valid[i])
         );
      end
   endgenerate

   generate
      for(i=0;i<NUM_KERNELS;i++) begin
         adder_tree #(
            .PRODUCT_WIDTH(PRODUCT_WIDTH),
            .NUM_INPUTS (WINDOW_ELEMENTS)
         ) u_adder_tree (
            .clk (clk),
            .rst_n (rst_n),

            .i_valid (w_products_valid[i]),
            .i_products (w_products[i]),

            .o_sum (w_accum[i]),
            .o_valid(w_accum_valid[i])
         );
      end
   endgenerate

   generate
      for(i=0;i<NUM_KERNELS;i++) begin
         round_saturate #(
            .IN_WIDTH(ACCUM_WIDTH),
            .OUT_WIDTH(FEATURE_WIDTH)
         ) u_round_saturate (
            .clk(clk),
            .rst_n(rst_n),
            
            .i_valid(w_accum_valid[i]),
            .i_data(w_accum[i]),
            
            .o_valid(w_feature_valid[i]),
            .o_data(w_feature[i])
         );
      end
   endgenerate

   generate
      for(i=0;i<NUM_KERNELS;i++) begin
         output_fifo #(
            .PIXEL_WIDTH (FEATURE_WIDTH),
            .DEPTH (FIFO_DEPTH),
            .PREFILL_THRESHOLD(FIFO_PREFILL_THRESHOLD)
         ) u_output_fifo (
            .clk (clk),
            .rst_n (rst_n),

            .i_valid (w_feature_valid[i]),
            .i_data (w_feature[i]),

            .o_data (o_feature[i]),
            .o_valid(w_o_valid[i])
         );
      end
   endgenerate

endmodule