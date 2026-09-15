// experiments/round_always_clamp: round half up with the positive clamp always built.
// Drop-in replacement for hw/ip/round_saturate, used only to measure its cost in the
// complete conv_system (fpga flow: RTL round_always_clamp).
//------------------------------------------------------------------------------
// Module: round_saturate
//
// Description:
//   Narrows a signed IN_WIDTH value to OUT_WIDTH bits by dropping
//   DROP = IN_WIDTH - OUT_WIDTH low bits with ROUND HALF UP, and saturates
//   only when the caller's input range makes an overflow possible.
//   When IN_WIDTH <= OUT_WIDTH the input is sign-extended unchanged.
//
// Rounding: round half up
//   o = floor((x + 2^(DROP-1)) / 2^DROP) = truncate(x) + guard bit
//   where the guard bit is x[DROP-1], the first discarded bit. Exact ties
//   round toward +infinity. This is the requantisation rounding used by
//   quantised CNN inference (e.g. CMSIS-NN adds the half then shifts).
//
// Saturation: generated only when reachable
//   - Truncating an IN_WIDTH value by DROP bits always fits OUT_WIDTH bits.
//     The only overflow the rounding can cause is +1 code at the top:
//     truncate(x) == 2^(OUT_WIDTH-1)-1 with the guard bit set, i.e. inputs
//     x >= 2^(IN_WIDTH-1) - 2^(DROP-1).
//   - The negative side can never overflow: the most negative input divided
//     by 2^DROP is exactly -2^(OUT_WIDTH-1), and rounding up only increases.
//   - IN_MAX is the largest positive value the caller can ever present.
//     NEED_SAT = round(IN_MAX) > 2^(OUT_WIDTH-1)-1 is evaluated at
//     elaboration. When it is false the clamp is not built at all; when it is
//     true only the positive clamp is built (a single overflow flag).
//   - For conv_system with 8-bit pixels and weights and a 16-bit output,
//     IN_MAX = N*N*255*127 never reaches the limit for any kernel size, so
//     NEED_SAT is false. Left at its default (full input range), the module
//     is a safe general-purpose round-and-saturate block.
//
// Timing:
//   - Two stages, latency 2 in both generate branches:
//       stage A: bit select, guard bit, overflow flag (a 16-input AND) -> REG
//       stage B: OUT_WIDTH incrementer, clamp mux if built              -> REG
//   - o_valid is i_valid delayed by two; o_data holds between valids.
//
// Parameters:
//   IN_WIDTH : Width of the signed input.
//   OUT_WIDTH: Width of the signed output.
//   IN_MAX   : Largest positive input the caller can produce.
//------------------------------------------------------------------------------
module round_saturate #(
  parameter integer IN_WIDTH  = 20,
  parameter integer OUT_WIDTH = 16,
  parameter longint IN_MAX    = (longint'(1) << (IN_WIDTH - 1)) - 1
) (
    input  logic clk,
    input  logic rst_n,

    input  logic i_valid,
    input  logic signed [IN_WIDTH-1:0] i_data,

    output logic o_valid,
    output logic signed [OUT_WIDTH-1:0] o_data
);

  localparam integer DROP     = IN_WIDTH - OUT_WIDTH;
  localparam integer DROP_POS = (DROP > 0) ? DROP : 0;
  localparam integer DROP_M1  = (DROP > 0) ? DROP - 1 : 0;

  localparam logic signed [OUT_WIDTH-1:0] MAX_VAL = {1'b0, {(OUT_WIDTH-1){1'b1}}};
  localparam longint MAX_OUT = (longint'(1) << (OUT_WIDTH - 1)) - 1;

  // Largest output the rounding can produce from the caller's range.
  localparam longint ROUNDED_MAX = (IN_MAX + (longint'(1) << DROP_M1)) >> DROP_POS;
  localparam bit     NEED_SAT    = (DROP > 0);   // experiment: clamp built even when unreachable

  logic signed [OUT_WIDTH-1:0] w_o_data;
  logic                        r_valid_s1;

  generate
    if (DROP > 0) begin : gen_round

      logic signed [OUT_WIDTH-1:0] w_trunc_val;
      logic                        w_guard_bit;
      logic                        w_overflow;

      assign w_trunc_val = i_data[IN_WIDTH-1:DROP];
      assign w_guard_bit = i_data[DROP-1];

      if (NEED_SAT) begin : gen_ovf_flag
        // +1 would carry out of the positive range.
        assign w_overflow = (w_trunc_val == MAX_VAL) & w_guard_bit;
      end
      else begin : gen_no_ovf_flag
        assign w_overflow = 1'b0;
      end

      // Stage A register.
      logic signed [OUT_WIDTH-1:0] r_trunc_val;
      logic                        r_guard_bit;
      logic                        r_overflow;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          r_trunc_val <= '0;
          r_guard_bit <= 1'b0;
          r_overflow  <= 1'b0;
        end
        else if (i_valid) begin
          r_trunc_val <= w_trunc_val;
          r_guard_bit <= w_guard_bit;
          r_overflow  <= w_overflow;
        end
      end

      // Stage B: round half up. Cannot wrap unless r_overflow is set, and
      // r_overflow can only be set when the clamp exists.
      logic signed [OUT_WIDTH-1:0] w_rounded;
      assign w_rounded = r_trunc_val + OUT_WIDTH'(r_guard_bit);

      if (NEED_SAT) begin : gen_sat
        assign w_o_data = r_overflow ? MAX_VAL : w_rounded;
      end
      else begin : gen_no_sat
        assign w_o_data = w_rounded;
      end
    end

    // No bits dropped: sign-extend. Registered once here so the latency
    // matches gen_round.
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
    if (!rst_n)
      o_data <= '0;
    else if (r_valid_s1)
      o_data <= w_o_data;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_valid_s1 <= 1'b0;
      o_valid    <= 1'b0;
    end
    else begin
      r_valid_s1 <= i_valid;
      o_valid    <= r_valid_s1;
    end
  end

endmodule
