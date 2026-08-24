module MAC_array #(
    parameter integer IMG_SIZE      = 32,
    parameter integer KERNEL_SIZE   = 3,
    parameter integer PIXEL_WIDTH   = 8,
    parameter integer KERNEL_COEF_WIDTH = 8,
    parameter integer OUT_PIXEL_WIDTH = 16,
    parameter integer WINDOW_SIZE   = KERNEL_SIZE*KERNEL_SIZE,
    parameter integer WINDOW_WIDTH  = PIXEL_WIDTH*WINDOW_SIZE,
    parameter integer K_WINDOW_WIDTH  = KERNEL_COEF_WIDTH*WINDOW_SIZE
) (
    input clk,
    input rst_n,
    input [WINDOW_WIDTH-1:0] i_window,
    input signed [K_WINDOW_WIDTH-1:0] i_kernel,
    input  i_window_valid,

    output signed [OUT_PIXEL_WIDTH-1:0] o_conv_pixel,
    output o_pixel_valid
);
localparam integer PROD_WIDTH = PIXEL_WIDTH + KERNEL_COEF_WIDTH; 
localparam integer NUM_TREE_STAGES  = $clog2(WINDOW_SIZE);
localparam integer FINAL_SUM_WIDTH  = PROD_WIDTH + NUM_TREE_STAGES;

wire [PIXEL_WIDTH-1:0] w_window_array [0:WINDOW_SIZE-1] ;
wire signed [PIXEL_WIDTH-1:0] w_kernel_array [0:WINDOW_SIZE-1] ;    
wire signed [FINAL_SUM_WIDTH-1:0] w_final_sum;
wire w_prod_valid ;
wire signed [PROD_WIDTH-1:0] w_adder_tree_0 [0:WINDOW_SIZE-1];
wire signed [OUT_PIXEL_WIDTH-1:0] w_out_pixel ;
reg signed [OUT_PIXEL_WIDTH-1:0] r_out_pixel ;
reg r_ro_sa_valid;


(* use_dsp = "yes" *) reg signed [PROD_WIDTH-1:0] r_products [0:WINDOW_SIZE-1] ; 
reg r_prod_valid ;
reg r_stage_valid [0:NUM_TREE_STAGES-1];
reg signed [K_WINDOW_WIDTH-1:0] r_kernel;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        r_kernel <= 0;
    else
        r_kernel <= i_kernel;
end

genvar i;
generate
    for (i=0;i<WINDOW_SIZE;i=i+1) begin
        assign w_window_array [i] = i_window [i*PIXEL_WIDTH +:PIXEL_WIDTH] ;
        assign w_kernel_array [i] = r_kernel [i*PIXEL_WIDTH  +:PIXEL_WIDTH] ;
    end
endgenerate

genvar j,m,l;
generate
    for (j=0;j<WINDOW_SIZE;j=j+1) begin
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                r_products [j] <= 0 ;
            end else if (i_window_valid) begin
                r_products [j] <= w_window_array[j] * w_kernel_array[j] ;
            end
        end
    end
endgenerate

generate
    for (m = 0; m < WINDOW_SIZE; m = m + 1) begin : init
        assign w_adder_tree_0[m] = r_products[m];
    end
endgenerate

generate
    for (l = 0; l < NUM_TREE_STAGES; l = l + 1) begin : stage
        localparam integer IN_COUNT   = (WINDOW_SIZE + ((1<<l)-1)) >> l;      
        localparam integer OUT_COUNT  = (IN_COUNT + 1) / 2;                    
        localparam integer IN_WIDTH   = PROD_WIDTH + l;
        localparam integer OUT_WIDTH  = PROD_WIDTH + l + 1;

        wire signed [OUT_WIDTH-1:0] w_adder_tree [0:OUT_COUNT-1];
        reg  signed [OUT_WIDTH-1:0] r_adder_tree [0:OUT_COUNT-1];

        for (m = 0; m < IN_COUNT/2; m = m + 1) begin : add
            if (l == 0)
                assign w_adder_tree[m] = w_adder_tree_0[2*m] + w_adder_tree_0[2*m+1];
            else
                assign w_adder_tree[m] = stage[l-1].r_adder_tree[2*m] + stage[l-1].r_adder_tree[2*m+1];
        end

        if (IN_COUNT % 2 == 1) begin : carry
            if (l == 0)
                assign w_adder_tree[OUT_COUNT-1] = w_adder_tree_0[IN_COUNT-1];
            else
                assign w_adder_tree[OUT_COUNT-1] = stage[l-1].r_adder_tree[IN_COUNT-1];
        end

        // register every entry of this stage's adder outputs
        if (l == 0) begin
            for (m = 0; m < OUT_COUNT; m = m + 1) begin : reg_stage
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    r_adder_tree[m] <= 0;
                else if (w_prod_valid)
                    r_adder_tree[m] <= w_adder_tree[m];
                end
            end
        end 
        else begin
            for (m = 0; m < OUT_COUNT; m = m + 1) begin : reg_stage
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    r_adder_tree[m] <= 0;
                else
                    r_adder_tree[m] <= w_adder_tree[m];
                end
            end
        end

        if (l == 0) begin : valid0
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    r_stage_valid[l] <= 1'b0;
                else 
                    r_stage_valid[l] <= w_prod_valid;
            end
        end else begin : validN
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    r_stage_valid[l] <= 1'b0;
                else 
                    r_stage_valid[l] <= r_stage_valid[l-1];
            end 
        end
    end
endgenerate

assign w_final_sum = stage[NUM_TREE_STAGES-1].r_adder_tree[0] ;

round_saturate #(
    .IN_WIDTH(FINAL_SUM_WIDTH),
    .OUT_WIDTH(OUT_PIXEL_WIDTH)
) round_saturate (
    .i_data(w_final_sum),
    .o_data(w_out_pixel)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_out_pixel <= 0;
    end
    else if (r_stage_valid[NUM_TREE_STAGES-1]) begin
        r_out_pixel <= w_out_pixel;
    end
end



always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_prod_valid  <= 1'b0 ;
        r_ro_sa_valid <= 1'b0;
    end else begin
        r_prod_valid  <= i_window_valid ;
        r_ro_sa_valid <= r_stage_valid[NUM_TREE_STAGES-1] ;
    end
end

assign w_prod_valid = r_prod_valid ;
assign o_pixel_valid = r_ro_sa_valid ;

assign o_conv_pixel = r_out_pixel ;


    
endmodule