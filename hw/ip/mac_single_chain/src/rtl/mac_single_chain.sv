//------------------------------------------------------------------------------
// Module: mac_single_chain
//
// Description:
//   Windowed multiply-accumulate built as ONE systolic chain of
//   WINDOW_SIZE**2 DSP48 slices. Every product and every addition lives inside
//   a DSP; the module uses no fabric adders at all.
//
// Why:
//   The figure of merit charges LUTs + 50*DSPs + 100*BRAMs. The DSP count is
//   fixed at one multiply per tap, so LUTs are the only term left to cut. The
//   earlier version ran one chain per window row and reduced the row sums with
//   a fabric adder tree: 42 LUTs, and the critical path of the design. Chaining
//   all slices through PCOUT->PCIN makes that tree unnecessary.
//
// Architecture:
//   - Slice e computes  acc[e] = acc[e-1] + pixel[e] * weight[e]  on its
//     dedicated post-adder, with acc[e-1] arriving on PCIN.
//   - Slice e runs e cycles after slice 0, so tap e is held back e+1 cycles
//     (one input register plus e skew registers). The last two of those land
//     in the slice's AREG; the rest are flip-flops, which the figure of merit
//     does not charge. srl_style="register" keeps long skews out of SRLs,
//     which WOULD cost LUTs at larger kernel sizes.
//   - ROUND_BIAS (default 0) can fold a rounding bias in through slice 0's C
//     port. conv_system leaves it at 0: rounding stays in round_saturate, as in the other MAC architectures.
//   - Weights are static for a frame, so they need no skew; they are
//     registered once into each slice's BREG.
//
// Timing:
//   - Latency is 2 + WINDOW_SIZE**2 cycles: input skew register, MREG, then
//     one PREG per slice. o_valid reproduces i_valid delayed by exactly that.
//   - Every register-to-register path is either skew FF -> A port, or a
//     DSP-internal / PCOUT->PCIN path. No fabric logic sits between registers.
//
// Assumptions:
//   - i_pixels[WINDOW_SIZE*r + j] is row r, column tap j (window_generator's
//     ordering). The chain order does not change the sum.
//   - Pixels unsigned, weights signed; each pixel is zero-extended by one bit
//     so a single signed multiplier covers the mixed-sign product.
//   - The biased sum fits ACCUM_WIDTH: the largest positive sum is
//     WINDOW_ELEMENTS * 127 * 255, which leaves WINDOW_ELEMENTS * 383 of
//     headroom below 2^(ACCUM_WIDTH-1), always more than ROUND_BIAS.
//
// Parameters:
//   PIXEL_WIDTH : Width of each pixel and weight.
//   WINDOW_SIZE : Kernel dimension.
//   ROUND_BIAS  : Constant added into the sum (2^(DROP-1) for round half up).
//------------------------------------------------------------------------------
module mac_single_chain #(
   parameter  int  PIXEL_WIDTH = 8,
   parameter  int  WINDOW_SIZE = 3,
   parameter  int  ROUND_BIAS  = 0,

   localparam int  WINDOW_ELEMENTS = WINDOW_SIZE ** 2,
   localparam int  PRODUCT_WIDTH   = 2 * PIXEL_WIDTH,
   localparam int  ACCUM_WIDTH     = PRODUCT_WIDTH + $clog2(WINDOW_ELEMENTS),
   localparam type pixel_t   = logic [PIXEL_WIDTH-1:0],
   localparam type k_pixel_t = logic signed [PIXEL_WIDTH-1:0],
   localparam type operand_t = logic signed [PIXEL_WIDTH:0],
   localparam type accum_t   = logic signed [ACCUM_WIDTH-1:0]
)(
   input  logic     clk,
   input  logic     rst_n,

   input  logic     i_valid,
   input  pixel_t   i_pixels [WINDOW_ELEMENTS],
   input  k_pixel_t i_weights[WINDOW_ELEMENTS],

   output accum_t   o_sum,
   output logic     o_valid
);

   // Input skew register, MREG, then one PREG per slice.
   localparam int LATENCY = 2 + WINDOW_ELEMENTS;

   logic r_valid [LATENCY];

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         for (int s = 0; s < LATENCY; s++) r_valid[s] <= 1'b0;
      else begin
         r_valid[0] <= i_valid;
         for (int s = 1; s < LATENCY; s++) r_valid[s] <= r_valid[s-1];
      end
   end

   // Weights land in each slice's BREG.
   (* use_dsp = "yes" *) k_pixel_t r_weight [WINDOW_ELEMENTS];

   always_ff @(posedge clk)
      for (int e = 0; e < WINDOW_ELEMENTS; e++)
         r_weight[e] <= i_weights[e];

   (* use_dsp = "yes" *) accum_t r_m   [WINDOW_ELEMENTS];   // MREG
   (* use_dsp = "yes" *) accum_t r_acc [WINDOW_ELEMENTS];   // PREG

   genvar e;
   generate
      for (e = 0; e < WINDOW_ELEMENTS; e++) begin : gen_tap

         // r_dly[d] is tap e delayed d+1 cycles; slice e reads r_dly[e].
         (* srl_style = "register" *) operand_t r_dly [e+1];

         always_ff @(posedge clk) begin
            r_dly[0] <= operand_t'({1'b0, i_pixels[e]});
            for (int d = 1; d <= e; d++)
               r_dly[d] <= r_dly[d-1];
         end

         always_ff @(posedge clk)
            r_m[e] <= accum_t'(r_dly[e] * r_weight[e]);

         if (e == 0) begin : gen_head
            // C port carries the rounding bias: P = M + C.
            always_ff @(posedge clk)
               r_acc[0] <= r_m[0] + accum_t'(ROUND_BIAS);
         end : gen_head
         else begin : gen_link
            // P = PCIN + M.
            always_ff @(posedge clk)
               r_acc[e] <= r_acc[e-1] + r_m[e];
         end : gen_link
      end : gen_tap
   endgenerate

   assign o_sum   = r_acc[WINDOW_ELEMENTS-1];
   assign o_valid = r_valid[LATENCY-1];

endmodule
