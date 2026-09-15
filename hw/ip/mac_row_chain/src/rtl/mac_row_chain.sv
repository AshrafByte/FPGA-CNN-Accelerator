//------------------------------------------------------------------------------
// Module: mac_row_chain
//
// Description:
//   Windowed multiply-accumulate built as WINDOW_SIZE systolic DSP chains, one
//   per window row, followed by a short adder tree over the row sums. Used by
//   conv_system when MAC_SEL == 2 (row chains).
//
// Why:
//   The competition figure of merit weights resources as
//   LUTs + 50*DSPs + 100*BRAMs, so LUTs are the only term that moves once the
//   DSP count is fixed. Measured on the parallel-multiplier version, adder_tree
//   alone was 139 of the design's 243 LUTs (57%). The DSP48E1 has a post-adder
//   and a dedicated PCOUT->PCIN cascade path between vertically adjacent
//   slices; accumulating there instead of in fabric removes that adder tree at
//   no DSP cost.
//
// Architecture:
//   - One chain per window row. Chain r computes
//        sum_r = SUM over j of pixel(r,j) * weight(r,j)
//     as a rolling accumulation, stage j adding its own product to the partial
//     sum arriving from stage j-1.
//   - Stage j of a chain runs one cycle later than stage j-1, because the
//     partial sum has to pass through that stage's output register. The window
//     presents all WINDOW_SIZE**2 taps on the same cycle, so tap j must be held
//     back j cycles longer than tap 0 for the chain to accumulate taps from one
//     window rather than from j successive windows. Combined with the j cycles
//     of column delay the window generator already applied, tap j ends up 2j
//     cycles behind the row stream - the standard systolic FIR arrangement of
//     two registers per tap. These delays are flip-flops, which the figure of
//     merit does not charge for.
//   - Weights are static for the duration of a frame (kernel_register is loaded
//     before streaming begins), so they need no matching skew.
//   - The WINDOW_SIZE row sums emerge aligned, because every chain is
//     structurally identical, and are reduced by a balanced adder tree. For a
//     3x3 window that is two adds, against the fifteen the full tree needed.
//
// Bit widths in the reduction tree:
//   - Each product fits PRODUCT_WIDTH signed bits: a 9-bit non-negative
//     operand times an 8-bit signed weight spans [-32640, +32385].
//   - A sum of m products therefore fits PRODUCT_WIDTH + $clog2(m) bits, since
//     m * 2^(PRODUCT_WIDTH-1) <= 2^(PRODUCT_WIDTH-1+$clog2(m)).
//   - A row sum covers WINDOW_SIZE products, so it enters the tree at
//     ROW_WIDTH = PRODUCT_WIDTH + $clog2(WINDOW_SIZE) bits rather than the full
//     ACCUM_WIDTH the DSP chain carries.
//   - As in the baseline adder_tree, every level grows by exactly one bit
//     (level g output covers at most 2^(g+1) row sums), capped at ACCUM_WIDTH,
//     which the whole window's sum never exceeds. The cap matters at kernel
//     sizes whose $clog2 rounds up twice (e.g. 5x5: 19 -> 20 -> 21 -> 21).
//   - The last level is always exactly ACCUM_WIDTH, since
//     ROW_WIDTH + $clog2(WINDOW_SIZE) >= PRODUCT_WIDTH + $clog2(WINDOW_SIZE**2).
//
// Timing:
//   - Latency is WINDOW_SIZE (chain) + $clog2(WINDOW_SIZE) (row reduction)
//     cycles. o_valid reproduces i_valid delayed by exactly that much, so the
//     feature order and count are unchanged from the adder-tree version - only
//     the absolute latency differs.
//
// Assumptions:
//   - i_pixels[WINDOW_SIZE*r + j] is row r, column tap j, matching the ordering
//     window_generator produces.
//   - i_weights is stable across a frame.
//   - Pixels are unsigned, weights signed. Each pixel is zero-extended by one
//     bit so a single signed multiplier covers the mixed-sign product.
//
// Parameters:
//   PIXEL_WIDTH : Width of each pixel and weight.
//   WINDOW_SIZE : Kernel dimension.
//------------------------------------------------------------------------------
module mac_row_chain #(
   parameter  int  PIXEL_WIDTH = 8,
   parameter  int  WINDOW_SIZE = 3,

   localparam int  WINDOW_ELEMENTS = WINDOW_SIZE ** 2,
   localparam int  PRODUCT_WIDTH   = 2 * PIXEL_WIDTH,
   localparam int  ACCUM_WIDTH     = PRODUCT_WIDTH + $clog2(WINDOW_ELEMENTS),
   localparam int  ROW_STAGES      = WINDOW_SIZE,
   localparam int  TREE_STAGES     = $clog2(WINDOW_SIZE),
   localparam int  ROW_WIDTH       = PRODUCT_WIDTH + $clog2(WINDOW_SIZE),
   localparam type pixel_t   = logic [PIXEL_WIDTH-1:0],
   localparam type k_pixel_t = logic signed [PIXEL_WIDTH-1:0],
   localparam type operand_t = logic signed [PIXEL_WIDTH:0],
   localparam type accum_t   = logic signed [ACCUM_WIDTH-1:0],
   localparam type row_t     = logic signed [ROW_WIDTH-1:0]
)(
   input  logic     clk,
   input  logic     rst_n,

   input  logic     i_valid,
   input  pixel_t   i_pixels [WINDOW_ELEMENTS],
   input  k_pixel_t i_weights[WINDOW_ELEMENTS],

   output accum_t   o_sum,
   output logic     o_valid
);

   // One cycle for the input skew register, one for MREG, ROW_STAGES through
   // the accumulate chain, TREE_STAGES through the row reduction.
   localparam int LATENCY = 2 + ROW_STAGES + TREE_STAGES;

   // Valid runs alongside the data through exactly as many stages.
   logic r_valid [LATENCY];

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         for (int s = 0; s < LATENCY; s++) r_valid[s] <= 1'b0;
      else begin
         r_valid[0] <= i_valid;
         for (int s = 1; s < LATENCY; s++) r_valid[s] <= r_valid[s-1];
      end
   end

   // Weights registered so they land in each DSP's BREG. They are static for
   // the whole frame, so this costs a cycle of start-up latency and nothing in
   // the steady state - and no matching skew, unlike the pixel taps.
   (* use_dsp = "yes" *) k_pixel_t r_weight [WINDOW_ELEMENTS];

   always_ff @(posedge clk)
      for (int e = 0; e < WINDOW_ELEMENTS; e++)
         r_weight[e] <= i_weights[e];

   row_t w_row_sum [WINDOW_SIZE];

   genvar r, j;
   generate
      for (r = 0; r < WINDOW_SIZE; r++) begin : gen_row_chain

         // Tap j must arrive at stage j, which runs j cycles after stage 0.
         // r_skew[j][d] is tap j delayed by d+1 cycles, so stage j reads
         // r_skew[j][j] and gets a delay of j+1. Only 6 of the 9 declared
         // elements are on a path to an output; synthesis trims the rest.
         operand_t r_skew [WINDOW_SIZE][WINDOW_SIZE];

         for (j = 0; j < WINDOW_SIZE; j++) begin : gen_skew
            always_ff @(posedge clk) begin
               r_skew[j][0] <= operand_t'({1'b0, i_pixels[WINDOW_SIZE*r + j]});
               for (int d = 1; d < WINDOW_SIZE; d++)
                  r_skew[j][d] <= r_skew[j][d-1];
            end
         end : gen_skew

         // The cascade. The multiply is registered into MREG and the
         // accumulate into PREG, which is what lets the DSP48 reach its
         // datasheet Fmax - with the multiply and the post-add in one
         // combinational lump the slice cannot close 250 MHz on a -1 part.
         // Splitting them does not change the skew: multiply and accumulate
         // advance down the chain in lockstep, one stage per cycle.
         (* use_dsp = "yes" *) accum_t r_m   [WINDOW_SIZE];
         (* use_dsp = "yes" *) accum_t r_acc [WINDOW_SIZE];

         for (j = 0; j < WINDOW_SIZE; j++) begin : gen_stage
            always_ff @(posedge clk) begin
               r_m[j] <= accum_t'(r_skew[j][j] * r_weight[WINDOW_SIZE*r + j]);
            end

            if (j == 0) begin : gen_head
               always_ff @(posedge clk)
                  r_acc[0] <= r_m[0];
            end : gen_head
            else begin : gen_tail
               always_ff @(posedge clk)
                  r_acc[j] <= r_acc[j-1] + r_m[j];
            end : gen_tail
         end : gen_stage

         // A row sum of WINDOW_SIZE products needs only ROW_WIDTH bits; the
         // upper bits of the DSP's P output are pure sign extension and are
         // left unconnected.
         assign w_row_sum[r] = r_acc[WINDOW_SIZE-1][ROW_WIDTH-1:0];
      end : gen_row_chain
   endgenerate

   // ---- reduce the row sums -------------------------------------------------
   // Only $clog2(WINDOW_SIZE) stages: two adds for a 3x3 window.
   generate
      for (genvar g = 0; g < TREE_STAGES; g++) begin : gen_tree

         localparam int IN_COUNT  = (WINDOW_SIZE + ((1<<g)-1)) >> g;
         localparam int OUT_COUNT = (IN_COUNT + 1) / 2;
         // One bit of growth per level, as in the baseline adder_tree, capped
         // at ACCUM_WIDTH (see header).
         localparam int IN_WIDTH  = (g == 0) ? ROW_WIDTH
                                  : ((ROW_WIDTH + g < ACCUM_WIDTH) ? ROW_WIDTH + g : ACCUM_WIDTH);
         localparam int OUT_WIDTH = (ROW_WIDTH + g + 1 < ACCUM_WIDTH) ? ROW_WIDTH + g + 1 : ACCUM_WIDTH;
         localparam type in_t  = logic signed [IN_WIDTH-1:0];
         localparam type out_t = logic signed [OUT_WIDTH-1:0];

         in_t w_in [IN_COUNT];
         // Explicitly fabric: left to itself Vivado absorbs one of these adds
         // into a tenth DSP, and a DSP costs 50 in the figure of merit against
         // roughly 20 LUTs for the adder.
         (* use_dsp = "no" *) out_t r_level [OUT_COUNT];

         // Selected with a generate-if, not a ternary: a reference to
         // gen_tree[g-1] must not be elaborated at all when g == 0.
         if (g == 0) begin : gen_first
            for (genvar q = 0; q < IN_COUNT; q++)
               assign w_in[q] = w_row_sum[q];
         end : gen_first
         else begin : gen_later
            for (genvar q = 0; q < IN_COUNT; q++)
               assign w_in[q] = gen_tree[g-1].r_level[q];
         end : gen_later

         // An odd operand count at this level passes the last one through
         // rather than building an adder for it. Chosen with a generate-if so
         // the pass-through never elaborates the missing w_in[2*k+1].
         for (genvar k = 0; k < OUT_COUNT; k++) begin : gen_add
            if (2*k + 1 < IN_COUNT) begin : gen_pair
               always_ff @(posedge clk or negedge rst_n) begin
                  if (!rst_n)
                     r_level[k] <= '0;
                  else
                     // Both operands sign-extended to OUT_WIDTH before the add.
                     r_level[k] <= out_t'(w_in[2*k]) + out_t'(w_in[2*k+1]);
               end
            end : gen_pair
            else begin : gen_pass
               always_ff @(posedge clk or negedge rst_n) begin
                  if (!rst_n)
                     r_level[k] <= '0;
                  else
                     r_level[k] <= out_t'(w_in[2*k]);
               end
            end : gen_pass
         end : gen_add
      end : gen_tree
   endgenerate

   // The last level is ACCUM_WIDTH wide by construction; the cast is a no-op.
   assign o_sum   = accum_t'(gen_tree[TREE_STAGES-1].r_level[0]);
   assign o_valid = r_valid[LATENCY-1];

endmodule
