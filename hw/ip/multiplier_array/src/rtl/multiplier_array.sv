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
//   - No shared logic between lanes — each product is computed and
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
//   - i_pixels[i] and i_weights[i] correspond to the same tap index i —
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
   localparam type product_t = logic [2*PIXEL_WIDTH-1:0]
)(
   input  logic     clk,
   input  logic     rst_n,
   input  logic     i_valid,

   input  pixel_t   i_pixels [INPUTS_NUM],
   input  pixel_t   i_weights[INPUTS_NUM],

   output product_t o_products[INPUTS_NUM],
   output logic     o_valid
);

   (* use_dsp = "yes" *) product_t r_products[INPUTS_NUM];
   product_t w_products[INPUTS_NUM];
   logic     r_valid_out;

   assign o_products  = r_products;
   assign o_valid = r_valid_out;

   always_ff @(posedge clk or negedge rst_n) begin : product_registers

      if (!rst_n) begin : reset_product_registers
         r_products  <= '{default: '0};
         r_valid_out <= 1'b0;
      end : reset_product_registers

      else begin : update_product_registers
         r_products  <= w_products;
         r_valid_out <= i_valid;
      end : update_product_registers

   end : product_registers

   always_comb begin : product_multipliers
      w_products = '{default: '0};
      for (int i = 0; i < INPUTS_NUM; i++)
         w_products[i] = i_pixels[i] * i_weights[i];
   end : product_multipliers

endmodule