//------------------------------------------------------------------------------
// Module: adder_tree
//
// Description:
//   Pipelined binary reduction tree that sums NUM_INPUTS product values into
//   a single accumulated result. The tree consists of NUM_STAGES combinational
//   adder levels, with a register stage after each level. An additional input
//   register stage captures the incoming product array and valid signal.
//
// Architecture:
//   - Stage 0 captures the incoming product array and i_valid.
//   - Each reduction stage performs pairwise additions between operands from
//     the previous stage and registers the results.
//   - The number of operands is approximately halved at every stage until
//     a single accumulated result remains.
//   - If a stage contains an odd number of operands, the final operand is
//     passed through unchanged without adding unnecessary hardware.
//   - Each reduction stage increases the data width by one bit, providing
//     sufficient width for the accumulated result without premature overflow.
//   - The valid signal propagates through the same pipeline stages as the
//     corresponding data.
//
// Data Flow:
//   - i_products are captured into the stage-0 registers together with
//     i_valid.
//   - Pairwise additions are performed combinationally between registered
//     operands.
//   - Each reduction level registers its results before passing them to the
//     following level.
//   - o_sum provides the final accumulated result.
//   - o_valid indicates when o_sum contains valid data.
//
// Timing:
//   - One register stage is used after each binary reduction level.
//   - The combinational critical path of each reduction stage contains only
//     one adder.
//   - The complete input-to-output latency is NUM_STAGES + 1 clock cycles,
//     including the initial input register stage.
//
// Assumptions:
//   - i_products are stable and valid when i_valid is asserted.
//   - NUM_INPUTS is greater than zero.
//   - Product values are unsigned. Signed arithmetic must be introduced
//     explicitly if signed products are required.
//   - The accumulator width is sufficient to represent the sum of all
//     NUM_INPUTS products.
//
// Parameters:
//   PRODUCT_WIDTH : Width of each input product.
//   NUM_INPUTS    : Number of product values entering the reduction tree.
//------------------------------------------------------------------------------
(* use_dsp = "no" *)
module adder_tree
   #(
      parameter int PRODUCT_WIDTH = 16,
      parameter int NUM_INPUTS    = 9,

      localparam int  NUM_STAGES = $clog2(NUM_INPUTS),
      localparam type product_t  = logic signed [PRODUCT_WIDTH-1:0],
      localparam type accum_t    = logic signed [PRODUCT_WIDTH + NUM_STAGES - 1:0]
   )(
      input logic clk,
      input logic rst_n,

      input logic i_valid,
      input product_t i_products[NUM_INPUTS],

      output accum_t o_sum,
      output logic   o_valid
   );

   logic     r_valid [NUM_STAGES];

   genvar g, k;
   generate
      for (g = 0; g < NUM_STAGES; g++) begin : stage

         localparam integer IN_COUNT   = (NUM_INPUTS + ((1<<g)-1)) >> g;
         localparam integer OUT_COUNT  = (IN_COUNT + 1) / 2;
         localparam integer IN_WIDTH   = PRODUCT_WIDTH + g;
         localparam integer OUT_WIDTH  = PRODUCT_WIDTH + g + 1;
         localparam type out_t     = logic signed [OUT_WIDTH-1:0];

         out_t w_stage_out[OUT_COUNT];
         out_t r_stage_out[OUT_COUNT];

         for (k = 0; k < IN_COUNT/2; k++) begin : stage_adder
            if (g == 0)
                assign w_stage_out[k] = i_products[2*k] + i_products[2*k+1];
            else
                assign w_stage_out[k] = stage[g-1].r_stage_out[2*k] + stage[g-1].r_stage_out[2*k+1];
         end : stage_adder

         if (IN_COUNT % 2 == 1) begin : carry
            if (g == 0)
                assign w_stage_out[OUT_COUNT-1] = i_products[IN_COUNT-1];
            else
                assign w_stage_out[OUT_COUNT-1] = stage[g-1].r_stage_out[IN_COUNT-1];
         end : carry

         for (k = 0; k < OUT_COUNT; k++) begin : reg_stage
            always_ff @(posedge clk or negedge rst_n) begin
               if (!rst_n)
                  r_stage_out[k] <= 0;
               else 
                  r_stage_out[k] <= w_stage_out[k];
            end
         end : reg_stage

         if (g==0) begin
            always_ff @(posedge clk or negedge rst_n) begin 
               if (!rst_n)
                  r_valid[g] <= 1'b0;
               else 
                  r_valid[g] <= i_valid;
            end
         end else begin
            always_ff @(posedge clk or negedge rst_n) begin 
               if (!rst_n)
                  r_valid[g] <= 1'b0;
               else 
                  r_valid[g] <= r_valid[g-1];
            end
         end

      end : stage
endgenerate

   assign o_sum   = stage[NUM_STAGES-1].r_stage_out[0];
   assign o_valid = r_valid[NUM_STAGES-1];


endmodule
