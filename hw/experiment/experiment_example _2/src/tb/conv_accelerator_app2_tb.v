module conv_accelerator_app2_tb();

parameter integer IMG_SIZE      = 32;
parameter integer KERNEL_SIZE   = 3;
parameter integer PIXEL_WIDTH   = 8;
parameter integer KERNEL_COEF_WIDTH = 8;
parameter integer OUT_PIXEL_WIDTH = 16;
parameter integer WINDOW_SIZE   = KERNEL_SIZE*KERNEL_SIZE;
parameter integer MEM_COEF_DEPTH = $clog2(WINDOW_SIZE);

// --- golden-model derived sizing (mirrors MAC_array.v / round_saturate.v exactly) ---
localparam integer OUT_SIZE        = IMG_SIZE - KERNEL_SIZE + 1;
localparam integer TOTAL_OUTPUT    = OUT_SIZE * OUT_SIZE;          // 900
localparam integer PROD_WIDTH      = PIXEL_WIDTH + KERNEL_COEF_WIDTH;
localparam integer NUM_TREE_STAGES = $clog2(WINDOW_SIZE);
localparam integer FINAL_SUM_WIDTH = PROD_WIDTH + NUM_TREE_STAGES;
localparam integer DROP            = FINAL_SUM_WIDTH - OUT_PIXEL_WIDTH;

reg clk;
reg rst_n;
reg [PIXEL_WIDTH-1:0] i_pixel_data ;
reg i_pixel_valid ;

reg signed [KERNEL_COEF_WIDTH-1:0] i_weight ;
reg i_wgt_en ;
reg [MEM_COEF_DEPTH-1:0] i_wgt_address ;

wire signed [OUT_PIXEL_WIDTH-1:0] o_conv_pixel ;
wire o_pixel_valid ;


conv_accelerator_app2 #(
    .IMG_SIZE(IMG_SIZE),
    .KERNEL_SIZE(KERNEL_SIZE),
    .PIXEL_WIDTH(PIXEL_WIDTH),
    .KERNEL_COEF_WIDTH(KERNEL_COEF_WIDTH),
    .OUT_PIXEL_WIDTH(OUT_PIXEL_WIDTH),
    .WINDOW_SIZE(WINDOW_SIZE),
    .MEM_COEF_DEPTH(MEM_COEF_DEPTH)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .i_pixel_data(i_pixel_data),
    .i_pixel_valid(i_pixel_valid),
    .i_weight(i_weight),
    .i_wgt_en(i_wgt_en),
    .i_wgt_address(i_wgt_address),
    .o_conv_pixel(o_conv_pixel),
    .o_pixel_valid(o_pixel_valid)
);

initial clk = 0;
always #10 clk = ~clk ;
integer i;
initial begin
    rst_n = 0;
    i_pixel_data = 0;
    i_pixel_valid = 0;
    i_weight =0;
    i_wgt_en =0;
    i_wgt_address=0;
    #20;
    rst_n = 1;
    for (i=0;i<WINDOW_SIZE;i=i+1) begin
        #20;
        i_weight = i+1 ;
        i_wgt_en =1;
        i_wgt_address=i;
    end

    #60;
    i_pixel_valid=1;
    i_pixel_data=1;
    for (i=1;i<32*IMG_SIZE;i=i+1) begin
        #20 i_pixel_data = i+1 ;
    end
    // safety net in case fewer than TOTAL_OUTPUT valid pulses ever arrive
    #2000;
    $display("TIMEOUT: simulation ended before %0d valid outputs were captured (got %0d).", TOTAL_OUTPUT, out_count);
    finish_and_report();
end


// =====================================================================
// Golden reference model
// =====================================================================

reg [PIXEL_WIDTH-1:0]              exp_img    [0:IMG_SIZE*IMG_SIZE-1];
reg signed [KERNEL_COEF_WIDTH-1:0] exp_kernel [0:WINDOW_SIZE-1];
reg signed [OUT_PIXEL_WIDTH-1:0]   exp_out    [0:TOTAL_OUTPUT-1];

integer r, c, kr, kc, idx;
reg signed [FINAL_SUM_WIDTH-1:0] raw_sum;

// Mirrors round_saturate.v bit-for-bit
function signed [OUT_PIXEL_WIDTH-1:0] round_saturate_model;
    input signed [FINAL_SUM_WIDTH-1:0] sum_in;
    reg signed [FINAL_SUM_WIDTH:0] rounded;
    reg signed [OUT_PIXEL_WIDTH-1:0] max_val;
    reg signed [OUT_PIXEL_WIDTH-1:0] min_val;
    begin
        max_val = {1'b0, {(OUT_PIXEL_WIDTH-1){1'b1}}};
        min_val = {1'b1, {(OUT_PIXEL_WIDTH-1){1'b0}}};
        if (DROP > 0) begin
            rounded = sum_in + (1 <<< (DROP-1));
            if (rounded[FINAL_SUM_WIDTH] != rounded[FINAL_SUM_WIDTH-1]) begin
                round_saturate_model = rounded[FINAL_SUM_WIDTH] ? min_val : max_val;
            end else begin
                round_saturate_model = rounded[FINAL_SUM_WIDTH-1 -: OUT_PIXEL_WIDTH];
            end
        end else begin
            round_saturate_model = sum_in;
        end
    end
endfunction

initial begin
    // Pixel stream truncated to PIXEL_WIDTH bits, same as the testbench's 8-bit reg
    for (idx = 0; idx < IMG_SIZE*IMG_SIZE; idx = idx + 1)
        exp_img[idx] = (idx + 1) & {PIXEL_WIDTH{1'b1}};

    // Kernel weights: i_wgt_address = i, i_weight = i+1, row-major 3x3
    for (idx = 0; idx < WINDOW_SIZE; idx = idx + 1)
        exp_kernel[idx] = idx + 1;

    // Golden output matrix (valid cross-correlation + round_saturate)
    for (r = 0; r < OUT_SIZE; r = r + 1) begin
        for (c = 0; c < OUT_SIZE; c = c + 1) begin
            raw_sum = 0;
            for (kr = 0; kr < KERNEL_SIZE; kr = kr + 1) begin
                for (kc = 0; kc < KERNEL_SIZE; kc = kc + 1) begin
                    raw_sum = raw_sum +
                        exp_img[(r+kr)*IMG_SIZE + (c+kc)] * exp_kernel[kr*KERNEL_SIZE+kc];
                end
            end
            exp_out[r*OUT_SIZE + c] = round_saturate_model(raw_sum);
        end
    end
end


// =====================================================================
// Live self-check: only the first TOTAL_OUTPUT (900) valid samples,
// i.e. from the first o_pixel_valid pulse through the 900th.
// =====================================================================

integer out_count;
integer error_count;
integer exp_row, exp_col;
reg     checking_done;

initial begin
    out_count     = 0;
    error_count   = 0;
    checking_done = 0;
end

always @(posedge clk) begin
    if (o_pixel_valid && !checking_done) begin
        exp_row = out_count / OUT_SIZE;
        exp_col = out_count % OUT_SIZE;
        if (o_conv_pixel !== exp_out[out_count]) begin
            error_count = error_count + 1;
            $display("MISMATCH #%0d @ time %0t : out_index=%0d (row=%0d, col=%0d)  sim=%0d (0x%0h)  expected=%0d (0x%0h)",
                error_count, $time, out_count, exp_row, exp_col,
                o_conv_pixel, o_conv_pixel, exp_out[out_count], exp_out[out_count]);
        end

        out_count = out_count + 1;

        if (out_count == TOTAL_OUTPUT) begin
            checking_done = 1;
            finish_and_report();
        end
    end
end

task finish_and_report;
    begin
        $display("=====================================================");
        $display("Self-check complete (first %0d valid outputs, out_index 0..%0d).", TOTAL_OUTPUT, TOTAL_OUTPUT-1);
        $display("  Captured outputs : %0d", out_count);
        $display("  Mismatches       : %0d", error_count);
        if (error_count == 0 && out_count == TOTAL_OUTPUT)
            $display("  RESULT: PASS - all %0d outputs match the golden model.", TOTAL_OUTPUT);
        else
            $display("  RESULT: FAIL - see MISMATCH lines above for details.");
        $display("=====================================================");
        $stop();
    end
endtask

endmodule