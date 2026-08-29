//------------------------------------------------------------------------------
// Module: adder_tree
//
// Description:
//   Generic pipelined binary reduction tree that sums NUM_INPUTS values into
//   a single accumulated result. Structure is generated at elaboration time
//   to support any NUM_INPUTS, odd or even, with one register stage per
//   level of the tree.
//
// Architecture:
//   - Built with generate/genvar as a binary tree, NUM_STAGES = $clog2(NUM_INPUTS) deep.
//   - Each stage halves the number of live values (ceil-division), pairing
//     adjacent elements and registering their sum.
//   - Odd element counts at any stage are registered through unchanged to
//     the next stage rather than padded, keeping adder count at the
//     minimum (N-1) regardless of pipelining.
//
// Data Flow:
//   - i_products are registered into stage 0 of the tree, alongside i_valid_in.
//   - Each stage registers the pairwise sum (or passthrough) of the previous
//     stage's values, and its own valid bit shadowing the data one stage
//     behind the stage before it.
//   - The final single value and valid bit are driven out as o_sum/o_valid_out.
//
// Timing:
//   - One register stage per tree level: NUM_STAGES cycles of latency.
//   - Critical path per stage is a single adder (tree-shaped reduction),
//     not the full N-1 chain, so timing closure does not worsen as
//     NUM_INPUTS grows — only latency does.
//
// Assumptions:
//   - i_products are valid and stable whenever i_valid_in is asserted.
//   - Caller tracks the module's NUM_STAGES-cycle latency only via
//     o_valid_out — no separate latency parameter is needed anywhere else
//     in the design.
//
// Parameters:
//   PRODUCT_WIDTH : Bit width of each input value.
//   NUM_INPUTS    : Number of values to sum; may be any positive integer.
//------------------------------------------------------------------------------
module adder_tree #(
   parameter  int  PRODUCT_WIDTH = 16,
   parameter  int  NUM_INPUTS    = 9,

   localparam int  NUM_STAGES = $clog2(NUM_INPUTS),
   localparam type product_t = logic [PRODUCT_WIDTH-1:0],
   localparam type accum_t   = logic [PRODUCT_WIDTH + NUM_STAGES - 1:0]
)(
   input  logic     clk,
   input  logic     rst_n,
   input  logic     i_valid_in,

   input  product_t i_products[NUM_INPUTS],

   output accum_t   o_sum,
   output logic     o_valid_out
);

   function automatic int stage_count(int stage);
      int c = NUM_INPUTS;
      for (int s = 0; s < stage; s++)
         c = (c + 1) / 2;
      return c;
   endfunction

   accum_t r_stage[NUM_STAGES+1][NUM_INPUTS];
   logic   r_valid[NUM_STAGES+1];

   always_ff @(posedge clk or negedge rst_n) begin: stage0_register
      if (!rst_n) begin
         r_stage[0] <= '{default: '0};
         r_valid[0] <= 1'b0;
      end else begin
         for (int i = 0; i < NUM_INPUTS; i++)
            r_stage[0][i] <= accum_t'(i_products[i]);
         r_valid[0] <= i_valid_in;
      end
   end: stage0_register

   genvar g, k;
   generate
      for (g = 0; g < NUM_STAGES; g++) begin : reduction_stage
         localparam int IN_COUNT  = stage_count(g);
         localparam int OUT_COUNT = stage_count(g+1);

         for (k = 0; k < OUT_COUNT; k++) begin : stage_adder
            if (2*k+1 < IN_COUNT) begin : paired_addition
               always_ff @(posedge clk or negedge rst_n) begin
                  if (!rst_n) r_stage[g+1][k] <= '0;
                  else        r_stage[g+1][k] <= r_stage[g][2*k] + r_stage[g][2*k+1];
               end
            end else begin : unpaired_passthrough
               always_ff @(posedge clk or negedge rst_n) begin
                  if (!rst_n) r_stage[g+1][k] <= '0;
                  else        r_stage[g+1][k] <= r_stage[g][2*k];
               end
            end
         end

         always_ff @(posedge clk or negedge rst_n) begin: stage_valid
            if (!rst_n) r_valid[g+1] <= 1'b0;
            else        r_valid[g+1] <= r_valid[g];
         end: stage_valid
      end
   endgenerate

   assign o_sum       = r_stage[NUM_STAGES][0];
   assign o_valid_out = r_valid[NUM_STAGES];

endmodule