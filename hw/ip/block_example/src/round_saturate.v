module round_saturate #(
    parameter IN_WIDTH  = 20,
    parameter OUT_WIDTH = 16
) (
    input  wire signed [IN_WIDTH-1:0]  i_data,
    output reg  signed [OUT_WIDTH-1:0] o_data
);

    localparam integer DROP = IN_WIDTH - OUT_WIDTH;
    localparam signed [OUT_WIDTH-1:0] MAX_VAL = {1'b0, {(OUT_WIDTH-1){1'b1}}};
    localparam signed [OUT_WIDTH-1:0] MIN_VAL = {1'b1, {(OUT_WIDTH-1){1'b0}}};
    
    // Half step for symmetric/convergent rounding
    localparam signed [IN_WIDTH:0] HALF_STEP = (DROP > 0) ? (1 <<< (DROP - 1)) : 0;

    generate
        if (DROP > 0) begin : gen_round_sat
            // 1. Add rounding offset with sign-extended MSB
            wire signed [IN_WIDTH:0] rounded = {i_data[IN_WIDTH-1], i_data} + HALF_STEP;
            
            // 2. Extract sign bits
            wire sign_extended = rounded[IN_WIDTH];
            wire sign_sliced   = rounded[IN_WIDTH-1];

            // 3. 1-LUT-level multiplexer
            always @(*) begin
                case ({sign_extended, sign_sliced})
                    2'b01:   o_data = MAX_VAL;                     // Positive overflow
                    2'b10:   o_data = MIN_VAL;                     // Negative underflow
                    default: o_data = rounded[IN_WIDTH-1 : DROP];  // Valid range (wire slice)
                endcase
            end
        end else begin : gen_passthrough
            // IN_WIDTH <= OUT_WIDTH (sign-extend if smaller)
            always @(*) begin
                o_data = {{(OUT_WIDTH-IN_WIDTH){i_data[IN_WIDTH-1]}}, i_data};
            end
        end
    endgenerate

endmodule