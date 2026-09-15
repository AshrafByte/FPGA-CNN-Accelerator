//------------------------------------------------------------------------------
// Module: relu_unit
//
// Description:
//   Registered rectified-linear activation for a single feature lane. Passes
//   non-negative features through unchanged and replaces negative features
//   with zero:
//
//     o_feature = (i_feature < 0) ? 0 : i_feature
//
// Architecture:
//   - The activation itself is a one-bit decision, not a comparison: for a
//     two's-complement value the sign bit IS the "< 0" predicate, so the
//     whole function is a mux select off i_feature[FEATURE_WIDTH-1]. No
//     comparator, no arithmetic, no carry chain - this synthesises to
//     FEATURE_WIDTH AND gates.
//   - A single output register stage follows the mux, matching the
//     valid-with-data latency convention used by every other stage in the
//     conv_system pipeline (multiplier_array, adder_tree, round_saturate).
//   - Purely feed-forward and lane-local: no handshake, no back-pressure, no
//     state beyond the output register. Instantiate one per kernel lane.
//
// Data Flow:
//   - i_feature is muxed against zero on its sign bit into w_feature.
//   - w_feature is captured into o_feature on the next rising clk edge,
//     but only while i_valid is high.
//   - i_valid is registered unconditionally into o_valid.
//
// Timing:
//   - Latency is exactly one clock cycle: a feature presented with i_valid
//     high on edge N appears on o_feature with o_valid high on edge N+1.
//   - o_valid is a plain one-cycle-delayed copy of i_valid, so gaps in the
//     input stream are reproduced exactly, shifted by one cycle.
//   - o_feature HOLDS its previous value while i_valid is low. This is
//     deliberate and matches round_saturate: o_feature is only meaningful
//     when o_valid is high, and holding avoids a needless register toggle
//     (and its dynamic power) on idle cycles.
//
// Assumptions:
//   - i_feature is two's-complement signed, which is what makes the sign-bit
//     mux equivalent to a compare against zero. Driving an unsigned value in
//     would zero every feature whose MSB is set.
//   - Downstream consumers gate on o_valid and never sample o_feature on an
//     invalid cycle.
//   - rst_n is asynchronous, active-low, and shared with the rest of the
//     pipeline.
//
// Parameters:
//   FEATURE_WIDTH : Width of the signed input and output feature.
//------------------------------------------------------------------------------
module relu_unit #(
    parameter int FEATURE_WIDTH = 16,

    localparam type feature_t = logic signed [FEATURE_WIDTH-1:0]
) (
    input  logic     clk,
    input  logic     rst_n,

    input  logic     i_valid,
    input  feature_t i_feature,

    output logic     o_valid,
    output feature_t o_feature
);

    feature_t w_feature;

    
    assign w_feature = i_feature[FEATURE_WIDTH-1] ? '0 : i_feature;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid   <= 1'b0;
            o_feature <= '0;
        end
        else begin
            o_valid <= i_valid;
            if (i_valid)
                o_feature <= w_feature;
        end
    end

endmodule
