// experiments/round_half_even: round-to-nearest, ties-to-even with both clamps (the earlier design).
// Drop-in replacement for hw/ip/round_saturate, used only to measure its cost in the
// complete conv_system (fpga flow: RTL round_half_even).
//------------------------------------------------------------------------------
// Module: round_saturate
//
// Description:
//   Converts a signed fixed-point value from IN_WIDTH bits to OUT_WIDTH bits
//   using round-to-nearest, ties-to-even (RNE) rounding followed by signed
//   saturation. When the input width is not greater than the output width,
//   the input is sign-extended without rounding.
//
// Architecture:
//   - Two-stage pipelined fixed-point rounding and saturation block.
//   - Retains the upper OUT_WIDTH bits as the truncated value.
//   - Uses the first discarded bit as the guard bit and an OR reduction of
//     all remaining discarded bits as the sticky bit.
//   - Implements ties-to-even by incrementing an exact-half result only when
//     the retained value is odd.
//   - Uses an OUT_WIDTH+1-bit incrementer to detect signed overflow without
//     requiring a full IN_WIDTH-bit rounding adder.
//   - Saturates positive overflow to MAX_VAL and negative overflow to MIN_VAL.
//
// Data Flow:
//   - i_data contains the signed input value.
//   - When IN_WIDTH > OUT_WIDTH, the lower DROP bits are discarded.
//   - w_guard_bit identifies whether the discarded portion reaches the
//     half-way point.
//   - w_sticky_bit identifies whether any discarded bit below the guard bit
//     is set.
//   - w_increment determines whether the retained value is incremented for
//     round-to-nearest, ties-to-even.
//   - The rounded value is checked for signed overflow before driving o_data.
//
// Rounding:
//   - Guard = 0:
//       The discarded value is less than one-half, so no increment occurs.
//
//   - Guard = 1, Sticky = 1:
//       The discarded value is greater than one-half, so the result is
//       incremented.
//
//   - Guard = 1, Sticky = 0:
//       The discarded value is exactly one-half. The result is incremented
//       only when the retained value is odd, producing an even result.
//
//   - The retained value LSB is therefore used only for the exact-half case.
//
// Saturation:
//   - Positive overflow is detected when the rounded result changes from
//     a positive sign representation to an invalid wider signed pattern.
//   - Negative overflow is detected when the rounded result changes from
//     a negative sign representation to an invalid wider signed pattern.
//   - Positive overflow produces MAX_VAL.
//   - Negative overflow produces MIN_VAL.
//   - Otherwise, the OUT_WIDTH least-significant bits of the rounded result
//     are passed to o_data.
//
// Timing:
//   - Latency is two clock cycles, and is the same in both generate branches
//     so it never depends on the width parameters.
//   - Stage A is bit-select plus the guard/sticky/increment decision - two
//     LUTs of logic. Stage B is the OUT_WIDTH+1 carry chain and the
//     saturation mux. The register between them exists because those two
//     halves together were the critical path of the whole accelerator.
//   - o_valid is a two-cycle-delayed copy of i_valid, so gaps in the input
//     stream are reproduced exactly, shifted by two.
//   - o_data HOLDS its previous value while the corresponding stage is idle;
//     it is only meaningful when o_valid is high.
//
// Assumptions:
//   - i_data uses two's-complement signed representation.
//   - IN_WIDTH and OUT_WIDTH are greater than or equal to 1.
//   - When IN_WIDTH > OUT_WIDTH, the lower DROP bits represent the
//     fixed-point precision being removed.
//   - The fixed-point binary-point position is unchanged by this block;
//     rounding only removes DROP least-significant bits.
//   - Saturation is required when the rounded result cannot be represented
//     by OUT_WIDTH signed bits.
//
// Parameters:
//   IN_WIDTH : Width of the signed input value.
//   OUT_WIDTH: Width of the signed output value.
//
//------------------------------------------------------------------------------
//
// Example:
//
//   IN_WIDTH  = 20
//   OUT_WIDTH = 16
//   DROP      = 4
//
//   Input:
//     [19:4] -> retained value
//     [3]    -> guard bit
//     [2:0]  -> sticky-bit reduction
//
//   Rounding decision:
//
//     G=0, S=X -> no increment
//     G=1, S=1 -> increment
//     G=1, S=0 -> increment only when retained LSB = 1
//
//------------------------------------------------------------------------------

module round_saturate #(
  parameter integer IN_WIDTH  = 20,
  parameter integer OUT_WIDTH = 16,
  // accepted for port compatibility with hw/ip/round_saturate; both clamps are always built
  parameter longint IN_MAX    = (longint'(1) << (IN_WIDTH - 1)) - 1
) (
    input  logic clk, 
    input  logic rst_n,

    input  logic i_valid,
    input  logic signed [IN_WIDTH-1:0] i_data,

    output logic o_valid,
    output logic signed [OUT_WIDTH-1:0] o_data
);

  localparam integer DROP = IN_WIDTH - OUT_WIDTH;
  localparam logic signed [OUT_WIDTH-1:0] MAX_VAL = {1'b0, {(OUT_WIDTH-1){1'b1}}};
  localparam logic signed [OUT_WIDTH-1:0] MIN_VAL = {1'b1, {(OUT_WIDTH-1){1'b0}}};

  logic signed [OUT_WIDTH-1:0] w_o_data;
  logic                        r_valid_s1;

  generate
    // Rounding and Saturation
    if (DROP > 0) begin : gen_round_sat

      logic signed  [OUT_WIDTH-1:0]     w_trunc_val;

      logic                             w_guard_bit;
      logic                             w_sticky_bit;

      logic                             w_increment;

      logic signed  [OUT_WIDTH:0]       w_rounded;
      logic                             w_sign_extended;
      logic                             w_sign_sliced;

      assign w_trunc_val = i_data[IN_WIDTH-1:DROP];

      // Guard bit
      // First discarded bit:
      //   0 -> discarded value is below half
      //   1 -> discarded value is at least half
      assign w_guard_bit = i_data[DROP-1];

      // Sticky bit
      // OR of all discarded bits after the guard bit:
      //   0 -> no additional discarded 1s
      //   1 -> at least one additional discarded 1

      if (DROP > 1) begin : gen_sticky
        assign w_sticky_bit = |i_data[DROP-2:0];
      end
      else begin : gen_no_sticky
        assign w_sticky_bit = 1'b0;
      end

      // Round-to-nearest, ties-to-even
      // Above half:
      //   guard = 1, sticky = 1 -> increment
      // Exact half:
      //   guard = 1, sticky = 0 -> increment only when retained value is odd.
      // Below half:
      //   guard = 0 -> no increment.

      assign w_increment = w_guard_bit & (w_sticky_bit | w_trunc_val[0]);

      // Pipeline register (stage A -> stage B)
      // Everything above is bit-select and two LUTs; everything below is a
      // full-width carry chain plus the saturation mux. Splitting here puts
      // the register between the two halves of what used to be the design's
      // critical path.
      logic signed [OUT_WIDTH-1:0] r_trunc_val;
      logic                        r_increment;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          r_trunc_val <= '0;
          r_increment <= 1'b0;
        end
        else if (i_valid) begin
          r_trunc_val <= w_trunc_val;
          r_increment <= w_increment;
        end
      end

      // Rounded value
      // One additional sign bit is retained to detect overflow.
      assign w_rounded = {r_trunc_val[OUT_WIDTH-1], r_trunc_val} + r_increment;

      // Saturation
      assign w_sign_extended = w_rounded[OUT_WIDTH];
      assign w_sign_sliced   = w_rounded[OUT_WIDTH-1];

      always_comb begin
        case ({w_sign_extended, w_sign_sliced})
          // Positive overflow.
          2'b01: begin
            w_o_data = MAX_VAL;
          end
          // Negative overflow.
          2'b10: begin
            w_o_data = MIN_VAL;
          end
          // Result is representable.
          default: begin
            w_o_data = w_rounded[OUT_WIDTH-1:0];
          end

        endcase
      end

    end

    // No Rounding Required
    // Still registered once here so this branch has the same 2-cycle latency
    // as gen_round_sat - the module's latency must not depend on its widths.
    else begin : gen_passthrough

      logic signed [OUT_WIDTH-1:0] r_extended;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
          r_extended <= '0;
        else if (i_valid)
          r_extended <= { {(OUT_WIDTH-IN_WIDTH){i_data[IN_WIDTH-1]}}, i_data };
      end

      assign w_o_data = r_extended;
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
      o_data <= '0 ;
    else if(r_valid_s1)
      o_data <= w_o_data ;
  end

  // Two valid stages to match the two data stages.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_valid_s1 <= 1'b0 ;
      o_valid    <= 1'b0 ;
    end
    else begin
      r_valid_s1 <= i_valid ;
      o_valid    <= r_valid_s1 ;
    end
  end

endmodule
