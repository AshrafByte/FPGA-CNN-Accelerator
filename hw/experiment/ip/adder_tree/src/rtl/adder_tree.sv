//------------------------------------------------------------------------------
// Module: adder_tree_comb
//
// Description:
//   Generic combinational binary reduction tree that sums NUM_INPUTS values
//   into a single accumulated result. Structure is generated at elaboration
//   time to support any NUM_INPUTS, odd or even.
//
// Architecture:
//   - Built with generate/genvar as a binary tree, NUM_STAGES = $clog2(NUM_INPUTS) deep.
//   - Each stage halves the number of live values (ceil-division), pairing
//     adjacent elements and adding them.
//   - Odd element counts at any stage are passed through unchanged to the
//     next stage rather than padded, keeping adder count at the minimum (N-1).
//
// Data Flow:
//   - i_products are zero/sign-extended into stage 0 of the tree.
//   - Each stage combinationally reduces pairs of values from the previous
//     stage, or passes an unpaired value straight through.
//   - The final single value at the last stage is driven out as o_sum.
//
// Timing:
//   - Fully combinational — no clk or rst_n, no internal registers.
//   - Critical path is NUM_STAGES adders deep (tree-shaped), not N-1 adders
//     deep (chain-shaped), regardless of latency being zero cycles.
//
// Assumptions:
//   - i_products are valid and stable whenever the caller intends to read o_sum.
//   - Caller is responsible for registering o_sum externally if pipelining
//     or a valid signal is required — this module carries neither.
//
// Parameters:
//   PRODUCT_WIDTH : Bit width of each input value.
//   NUM_INPUTS    : Number of values to sum; may be any positive integer.
//------------------------------------------------------------------------------

module adder_tree_comb #(
   parameter  int  PRODUCT_WIDTH = 16,
   parameter  int  NUM_INPUTS    = 9,

   localparam int  NUM_STAGES = $clog2(NUM_INPUTS),
   localparam type product_t = logic [PRODUCT_WIDTH-1:0],
   localparam type accum_t   = logic [PRODUCT_WIDTH + NUM_STAGES - 1:0]
)(
   input  product_t i_products[NUM_INPUTS],
   output accum_t   o_sum
);

   function automatic int stage_count(int stage);
      int c = NUM_INPUTS;
      for (int s = 0; s < stage; s++)
         c = (c + 1) / 2;
      return c;
   endfunction

   accum_t w_stage[NUM_STAGES+1][NUM_INPUTS];

   always_comb
      for (int i = 0; i < NUM_INPUTS; i++)
         w_stage[0][i] = accum_t'(i_products[i]);

   genvar g, k;
   generate
      for (g = 0; g < NUM_STAGES; g++) begin : gen_stage
         localparam int IN_COUNT  = stage_count(g);
         localparam int OUT_COUNT = stage_count(g+1);

         for (k = 0; k < OUT_COUNT; k++) begin : gen_adder
            if (2*k+1 < IN_COUNT) begin : gen_pair
               assign w_stage[g+1][k] = w_stage[g][2*k] + w_stage[g][2*k+1];
            end else begin : gen_passthrough
               assign w_stage[g+1][k] = w_stage[g][2*k];
            end
         end
      end
   endgenerate

   assign o_sum = w_stage[NUM_STAGES][0];

endmodule