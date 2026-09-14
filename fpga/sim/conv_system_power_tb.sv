//------------------------------------------------------------------------------
// Module: conv_system_power_tb
//
// Purpose:
//   Stimulus for the SAIF-based power benchmarks of the FPGA flow
//   (fpga/scripts/power.tcl). One frame: reset, load the kernel into every
//   lane, stream the image at one pixel per clock cycle with no stalls, drain.
//   xsim records the DUT's switching activity into conv.saif, which Vivado
//   reads back on the routed checkpoint.
//
//   IMAGE_MODE  1 : uniform random pixels 0..255 (fixed seed)
//               2 : pixel checkerboard 0x00/0xFF - every pixel bit toggles
//                   every cycle, the highest possible input activity
//               5 : vertical bars, 4 px black / 4 px white
//   KERNEL_MODE 0 : Sobel-X
//               1 : uniform random int8 weights, full range (fixed seed)
//               3 : Sobel-Y
//
//   Competition benchmarks (3x3):  bars + Sobel-X     = IMAGE 5, KERNEL 0
//                                  checker + Sobel-Y  = IMAGE 2, KERNEL 3
//   Other kernel sizes use random image + random kernel (IMAGE 1, KERNEL 1).
//
//   The Sobel weights are written in the order listed, straight into the tap
//   order of the kernel register (no host row reversal), exactly as the
//   measurements in the project results were taken. A column-mirrored Sobel
//   has the same switching activity, so the power is unaffected.
//
// Configuration arrives through power_cfg.vh, written by power.tcl, because
// the xelab .bat wrapper on Windows strips '=' from -generic arguments.
//------------------------------------------------------------------------------
`timescale 1ps/1ps

`include "power_cfg.vh"

module conv_system_power_tb;

   parameter int PIXEL_WIDTH   = 8;
   parameter int WINDOW_SIZE   = `WINDOW_SIZE_VAL;
   parameter int INPUT_SIZE    = `INPUT_SIZE_VAL;
   parameter int FEATURE_WIDTH = 16;
   parameter int NUM_KERNELS   = `NUM_KERNELS_VAL;
   parameter bit ENABLE_RELU   = 1'(`ENABLE_RELU_VAL);

   parameter int CLK_PS      = `CLK_PS_VAL;
   parameter int IMAGE_MODE  = `IMAGE_MODE_VAL;
   parameter int KERNEL_MODE = `KERNEL_MODE_VAL;

   localparam int WINDOW_ELEMENTS = WINDOW_SIZE ** 2;
   localparam int FRAME_PIXELS    = INPUT_SIZE * INPUT_SIZE;
   // Enough for the FIFO prefill and the longest MAC latency (the single chain
   // delays the last tap WINDOW_ELEMENTS cycles).
   localparam int DRAIN_CYCLES    = 4 * INPUT_SIZE + 64 + 2 * WINDOW_ELEMENTS + INPUT_SIZE * WINDOW_SIZE;

   typedef logic        [PIXEL_WIDTH-1:0]   data_t;
   typedef logic signed [PIXEL_WIDTH-1:0]   k_data_t;
   typedef logic signed [FEATURE_WIDTH-1:0] feature_t;

   logic clk = 1'b0;
   logic rst_n;

   data_t                          i_data;
   logic                           i_pixel_valid;
   logic                           i_weight_valid;
   logic [$clog2(NUM_KERNELS):0]   i_select_kernel;
   feature_t                       o_feature [NUM_KERNELS];
   logic                           o_valid;

   always #(CLK_PS/2) clk = ~clk;

   data_t   image  [FRAME_PIXELS];
   k_data_t kernel [WINDOW_ELEMENTS];

   int unsigned features_seen;

   conv_system #(
      .PIXEL_WIDTH   (PIXEL_WIDTH),
      .WINDOW_SIZE   (WINDOW_SIZE),
      .INPUT_SIZE    (INPUT_SIZE),
      .FEATURE_WIDTH (FEATURE_WIDTH),
      .NUM_KERNELS   (NUM_KERNELS),
      .ENABLE_RELU   (ENABLE_RELU)
   ) u_dut (
      .clk             (clk),
      .rst_n           (rst_n),
      .i_data          (i_data),
      .i_pixel_valid   (i_pixel_valid),
      .i_weight_valid  (i_weight_valid),
      .i_select_kernel (i_select_kernel),
      .o_feature       (o_feature),
      .o_valid         (o_valid)
   );

   always_ff @(posedge clk or negedge rst_n)
      if (!rst_n) features_seen <= 0;
      else if (o_valid) features_seen <= features_seen + 1;

   initial begin
      int unsigned seed = 32'd20260915;
      int dummy;

      dummy = $urandom(seed);

      case (KERNEL_MODE)
         // Sobel kernels are 3x3 only; written element by element so the
         // testbench still elaborates at other WINDOW_SIZEs.
         0: begin
               kernel[0] = -8'sd1; kernel[1] = 8'sd0; kernel[2] = 8'sd1;
               kernel[3] = -8'sd2; kernel[4] = 8'sd0; kernel[5] = 8'sd2;
               kernel[6] = -8'sd1; kernel[7] = 8'sd0; kernel[8] = 8'sd1;
            end
         3: begin
               kernel[0] = -8'sd1; kernel[1] = -8'sd2; kernel[2] = -8'sd1;
               kernel[3] =  8'sd0; kernel[4] =  8'sd0; kernel[5] =  8'sd0;
               kernel[6] =  8'sd1; kernel[7] =  8'sd2; kernel[8] =  8'sd1;
            end
         default:
            for (int k = 0; k < WINDOW_ELEMENTS; k++)
               kernel[k] = k_data_t'($urandom_range(0, 255));
      endcase

      case (IMAGE_MODE)
         1: for (int p = 0; p < FRAME_PIXELS; p++)
               image[p] = data_t'($urandom_range(0, 255));
         5: for (int p = 0; p < FRAME_PIXELS; p++)
               image[p] = (((p % INPUT_SIZE) / 4) % 2) ? 8'hFF : 8'h00;
         default:
            for (int p = 0; p < FRAME_PIXELS; p++)
               image[p] = (((p / INPUT_SIZE) + (p % INPUT_SIZE)) % 2) ? 8'hFF : 8'h00;
      endcase

      rst_n           = 1'b0;
      i_data          = '0;
      i_pixel_valid   = 1'b0;
      i_weight_valid  = 1'b0;
      i_select_kernel = '0;
      repeat (8) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);

      // The same kernel into every lane, lane by lane.
      for (int n = 0; n < NUM_KERNELS; n++)
         for (int k = 0; k < WINDOW_ELEMENTS; k++) begin
            i_weight_valid  <= 1'b1;
            i_select_kernel <= ($clog2(NUM_KERNELS)+1)'(n);
            i_data          <= data_t'(kernel[k]);
            @(posedge clk);
         end
      i_weight_valid  <= 1'b0;
      i_select_kernel <= '0;
      i_data          <= '0;
      repeat (4) @(posedge clk);

      $display("[POWER] IMAGE_MODE=%0d KERNEL_MODE=%0d kernel=%p", IMAGE_MODE, KERNEL_MODE, kernel);
      for (int p = 0; p < FRAME_PIXELS; p++) begin
         i_pixel_valid <= 1'b1;
         i_data        <= image[p];
         @(posedge clk);
      end
      i_pixel_valid <= 1'b0;
      i_data        <= '0;

      repeat (DRAIN_CYCLES) @(posedge clk);
      $display("[POWER] frame done: %0d features emitted (expected %0d)",
               features_seen, (INPUT_SIZE - WINDOW_SIZE + 1) ** 2);
      $finish;
   end

endmodule
