//------------------------------------------------------------------------------
// Module: adder_tree
//
// Description:
//   Generic pipelined binary reduction tree that sums NUM_INPUTS values into
//   a single accumulated result. Each stage's storage is sized to exactly
//   the width it needs (growing by one guard bit per stage), not padded to
//   the final accumulator width early — avoids unused high bits sitting
//   idle in every register below the final stage.
//
// Architecture:
//   - Built with generate/genvar as a binary tree, NUM_STAGES = $clog2(NUM_INPUTS) deep.
//   - Stage g's registers are exactly PRODUCT_WIDTH + g bits wide - the
//     minimum width that can hold the sum of up to 2^g raw inputs without
//     overflow, and no wider.
//   - Odd element counts at any stage are registered through unchanged to
//     the next stage rather than padded, keeping adder count at the
//     minimum (N-1) regardless of pipelining.
//
// Data Flow:
//   - i_products are registered into stage 0 at PRODUCT_WIDTH bits,
//     alongside i_valid_in.
//   - Each stage registers the pairwise sum (or passthrough) of the
//     previous stage's values at that stage's own (one-bit-wider) width,
//     and its own valid bit shadowing the data one stage behind.
//   - The final single value and valid bit are driven out as o_sum/o_valid_out.
//
// Timing:
//   - One register stage per tree level: NUM_STAGES cycles of latency.
//   - Critical path per stage is a single adder; timing closure does not
//     worsen as NUM_INPUTS grows, only latency does.
//
// Assumptions:
//   - i_products are valid and stable whenever i_valid_in is asserted.
//   - Caller tracks the module's NUM_STAGES-cycle latency only via
//     o_valid_out.
//
// Parameters:
//   PRODUCT_WIDTH : Bit width of each input value.
//   NUM_INPUTS    : Number of values to sum; may be any positive integer.
//------------------------------------------------------------------------------
module adder_tree
   #(
      parameter int PRODUCT_WIDTH = 16,
      parameter int NUM_INPUTS    = 9,

      localparam int  NUM_STAGES = $clog2(NUM_INPUTS),
      localparam type product_t  = logic [PRODUCT_WIDTH-1:0],
      localparam type accum_t    = logic [PRODUCT_WIDTH + NUM_STAGES - 1:0]
   )(
      input logic clk,
      input logic rst_n,
      input logic i_valid_in,

      input product_t i_products[NUM_INPUTS],

      output accum_t o_sum,
      output logic   o_valid_out
   );

   product_t r_stage0[NUM_INPUTS];
   logic     r_valid [NUM_STAGES+1];

   always_ff @(posedge clk or negedge rst_n) begin: stage0_register
      if (!rst_n) begin
         r_stage0   <= '{default: '0};
         r_valid[0] <= 1'b0;
      end else begin
         r_stage0   <= i_products;
         r_valid[0] <= i_valid_in;
      end
   end: stage0_register

   genvar g, k;
   generate
      for (g = 0; g < NUM_STAGES; g++) begin : reduction_stage

         localparam int  IN_COUNT  = stage_input_cnt(g);
         localparam int  OUT_COUNT = stage_input_cnt(g+1);
         localparam type out_t     = logic [PRODUCT_WIDTH+g:0];

         out_t r_stage_out[OUT_COUNT];

         for (k = 0; k < OUT_COUNT; k++) begin : stage_adder

            if (g == 0) begin : from_stage0

               if (2*k+1 < IN_COUNT) begin : paired_addition
                  always_ff @(posedge clk or negedge rst_n) begin
                     if (!rst_n) r_stage_out[k] <= '0;
                     else r_stage_out[k]        <= out_t'(r_stage0[2*k]) + out_t'(r_stage0[2*k+1]);
                  end
               end : paired_addition 
               
               else begin : unpaired_passthrough
                  always_ff @(posedge clk or negedge rst_n) begin
                     if (!rst_n) r_stage_out[k] <= '0;
                     else r_stage_out[k]        <= out_t'(r_stage0[2*k]);
                  end
               end : unpaired_passthrough

            end : from_stage0 

            else begin : from_prev_stage
               if (2*k+1 < IN_COUNT) begin : paired_addition
                  always_ff @(posedge clk or negedge rst_n) begin
                     if (!rst_n) r_stage_out[k] <= '0;
                     else r_stage_out[k]        <= out_t'(reduction_stage[g-1].r_stage_out[2*k])
                        + out_t'(reduction_stage[g-1].r_stage_out[2*k+1]);
                  end
               end : paired_addition 

               else begin : unpaired_passthrough
                  always_ff @(posedge clk or negedge rst_n) begin
                     if (!rst_n) r_stage_out[k] <= '0;
                     else r_stage_out[k]        <= out_t'(reduction_stage[g-1].r_stage_out[2*k]);
                  end
               end : unpaired_passthrough

            end : from_prev_stage

         end : stage_adder

         always_ff @(posedge clk or negedge rst_n) begin: stage_valid
            if (!rst_n) r_valid[g+1] <= 1'b0;
            else r_valid[g+1]        <= r_valid[g];
         end: stage_valid

      end : reduction_stage
   endgenerate

   assign o_sum       = reduction_stage[NUM_STAGES-1].r_stage_out[0];
   assign o_valid_out = r_valid[NUM_STAGES];

   function automatic int stage_input_cnt(int stage);
      int c = NUM_INPUTS;
      for (int s = 0; s < stage; s++)
         c = (c + 1) / 2;
      return c;
   endfunction

endmodule