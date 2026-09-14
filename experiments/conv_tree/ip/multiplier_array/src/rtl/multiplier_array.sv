//------------------------------------------------------------------------------
// Module: multiplier_array
//
// Description:
//   Fully parallel array of INPUTS_NUM multipliers, computing the elementwise
//   product of a pixel window against a matching set of kernel weights.
//   Each multiply is tagged to synthesize onto a dedicated DSP slice rather
//   than LUT fabric (Vivado-specific synthesis attribute).
//
// Architecture:
//   - INPUTS_NUM independent combinational multipliers, one per input pair.
//   - No shared logic between lanes - each product is computed and
//     registered fully in parallel with every other lane.
//   - (* use_dsp = "yes" *) on the product register instructs Vivado's
//     synthesis tool to map each multiply onto a hardware DSP48 slice
//     instead of LUT-based multiply logic, freeing LUT resources and
//     typically improving timing for the multiply itself.
//
// Data Flow:
//   - i_pixels and i_weights are multiplied elementwise, lane for lane.
//   - Products are registered and driven out as o_products.
//   - i_valid_in is registered alongside the products into o_valid_out.
//
// Timing:
//   - Multiplication is combinational; products and valid are captured on
//     the rising clock edge, giving the module one cycle of latency.
//
// Assumptions:
//   - i_pixels[i] and i_weights[i] correspond to the same tap index i -
//     caller is responsible for consistent ordering between the two arrays.
//   - i_valid_in reflects that both i_pixels and i_weights are valid and
//     stable on the same cycle.
//   - use_dsp is a Vivado-specific attribute; synthesizing this module on a
//     non-Xilinx toolchain will simply ignore it (no functional effect,
//     tool-dependent resource mapping only).
//
// Parameters:
//   PIXEL_WIDTH : Width of each input pixel and weight value.
//   INPUTS_NUM  : Number of parallel multiply lanes (e.g. WINDOW_SIZE**2).
//------------------------------------------------------------------------------
module multiplier_array #(
   parameter  int  PIXEL_WIDTH = 8,
   parameter  int  INPUTS_NUM  = 9,

   localparam type pixel_t   = logic [PIXEL_WIDTH-1:0],
   localparam type k_pixel_t = logic signed [PIXEL_WIDTH-1:0],
   localparam type product_t = logic signed [2*PIXEL_WIDTH-1:0]
)(
   input  logic     clk,
   input  logic     rst_n,
   input  logic     i_valid,

   input  pixel_t   i_pixels [INPUTS_NUM],
   input  k_pixel_t i_weights[INPUTS_NUM],

   output product_t o_products[INPUTS_NUM],
   output logic     o_valid
);
   localparam type operand_t = logic signed [PIXEL_WIDTH:0]; 

   // Three valid stages, one per DSP pipeline register the data passes through:
   // AREG/BREG, then MREG, then PREG. Adding MREG without extending this chain
   // would slide valid one cycle ahead of its data.
   logic r_s1_valid;
   logic r_s2_valid;
   logic r_s3_valid;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         r_s1_valid <= 1'b0;
         r_s2_valid <= 1'b0;
         r_s3_valid <= 1'b0;
      end else begin
         r_s1_valid <= i_valid;
         r_s2_valid <= r_s1_valid;
         r_s3_valid <= r_s2_valid;
      end
   end

   (* use_dsp = "yes" *) operand_t r_dsp_a [INPUTS_NUM];
   (* use_dsp = "yes" *) k_pixel_t r_dsp_b [INPUTS_NUM];
   (* use_dsp = "yes" *) product_t r_dsp_m [INPUTS_NUM];
   (* use_dsp = "yes" *) product_t r_products [INPUTS_NUM];

   genvar i;
   generate
      for (i = 0; i < INPUTS_NUM; i++) begin
         always_ff @(posedge clk) begin
               // Stage 1: DSP Input Registers (AREG=1, BREG=1)
               r_dsp_a[i] <= i_pixels[i];
               r_dsp_b[i] <= i_weights[i];

               // Stage 2: DSP Multiplier Register (MREG=1). Splitting the
               // multiply internally is what lets the DSP48 reach its datasheet
               // Fmax - without MREG the whole multiplier delay lands in one cycle.
               r_dsp_m[i] <= r_dsp_a[i] * r_dsp_b[i];

               // Stage 3: DSP Output Register (PREG=1)
               r_products[i] <= r_dsp_m[i];
            end
      end 
   endgenerate

   assign o_products = r_products;
   assign o_valid    = r_s3_valid;

endmodule
