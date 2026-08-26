module window_generation_app2 #(
    parameter integer IMG_SIZE      = 32,
    parameter integer KERNEL_SIZE   = 3,
    parameter integer PIXEL_WIDTH   = 8,
    parameter integer WINDOW_SIZE   = KERNEL_SIZE*KERNEL_SIZE,
    parameter integer WINDOW_WIDTH  = PIXEL_WIDTH*WINDOW_SIZE
) (
    input                           clk                 ,
    input                           rst_n               ,
    input       [PIXEL_WIDTH-1:0]   i_pixel_data        , 
    input                           i_pixel_valid       ,

    output      [WINDOW_WIDTH-1:0]  o_window            ,
    output                          o_window_valid      
);
localparam integer OUT_SIZE   = IMG_SIZE - KERNEL_SIZE + 1;
localparam integer TOTAL_INPUT  = IMG_SIZE * IMG_SIZE;
localparam integer TOTAL_OUTPUT = OUT_SIZE * OUT_SIZE;

localparam integer PRECHARGE_CYCLES = (TOTAL_INPUT - TOTAL_OUTPUT) + 30;

localparam integer PRECHARGE_LINES  = (PRECHARGE_CYCLES + IMG_SIZE - 1) / IMG_SIZE;
localparam integer NUM_LINE_BUFFERS = (PRECHARGE_LINES + 1 > KERNEL_SIZE + 1) ? (PRECHARGE_LINES + 2) : (KERNEL_SIZE + 2);
             
localparam integer COUNT_WIDTH = $clog2(IMG_SIZE);
localparam integer LB_DEPTH = $clog2(NUM_LINE_BUFFERS);  
localparam integer PC_DEPTH = $clog2(PRECHARGE_CYCLES);  

wire [LB_DEPTH-1:0] w_wr_en ;
wire w_start_process ;
wire [KERNEL_SIZE*PIXEL_WIDTH-1:0] bank_out_data [0:NUM_LINE_BUFFERS-1] ;

reg [LB_DEPTH-1:0] r_wr_en ;
reg [COUNT_WIDTH-1:0] r_row_cnt;
reg [COUNT_WIDTH-1:0] r_col_cnt;
reg [PC_DEPTH-1:0] r_start_process ;
reg [COUNT_WIDTH-1:0] r_rd_col_cnt ;
reg [WINDOW_WIDTH-1:0] r_window;

reg  [LB_DEPTH-1:0] r_bank_start ;
wire                 w_row_done   ;

genvar i;
generate
    for (i=0;i<NUM_LINE_BUFFERS;i=i+1) begin : bank
        line_buffer_app2 #(
            .IMG_SIZE(IMG_SIZE),
            .KERNEL_SIZE(KERNEL_SIZE),
            .PIXEL_WIDTH(PIXEL_WIDTH)
        ) u_bank (
            .clk(clk),
            .rst_n(rst_n),
            .i_wr_en((w_wr_en==i)? 1'b1 : 1'b0 ),
            .i_pixel_data(i_pixel_data),
            .i_wr_address(r_col_cnt),
            .i_rd_address(r_rd_col_cnt),
            .o_pixel_data(bank_out_data[i])
        );
    end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_row_cnt <= 0 ;
        r_col_cnt <= 0 ;
        r_wr_en <= 0 ;
    end
    else if (i_pixel_valid) begin
        if (r_col_cnt == IMG_SIZE - 1) begin
            r_col_cnt <= 0 ;
            r_wr_en <= (r_wr_en == NUM_LINE_BUFFERS-1) ? {LB_DEPTH{1'b0}} : r_wr_en + 1'b1 ;
            if (r_row_cnt == IMG_SIZE - 1)
                r_row_cnt <= 0 ;
            else
                r_row_cnt <= r_row_cnt + 1 ;
        end
        else begin
            r_col_cnt <= r_col_cnt + 1 ;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_start_process <= 0 ;
    end
    else if (i_pixel_valid && ~(r_start_process == PRECHARGE_CYCLES-1) ) begin
        r_start_process <= r_start_process + 1 ;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        r_rd_col_cnt <= 0 ;
    end 
    else if (w_start_process) begin
        if (r_rd_col_cnt==IMG_SIZE-KERNEL_SIZE) begin
            r_rd_col_cnt <= 0;
        end
        else begin
            r_rd_col_cnt <= r_rd_col_cnt + 1 ;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        r_bank_start <= 0;
    else if (w_row_done)
        r_bank_start <= (r_bank_start == NUM_LINE_BUFFERS-1) ? 0 : r_bank_start + 1'b1;
end

genvar k;
generate
    for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
        always @(*) begin
                r_window[k*(KERNEL_SIZE*PIXEL_WIDTH) +: KERNEL_SIZE*PIXEL_WIDTH]
                    = bank_out_data[(r_bank_start + k) % NUM_LINE_BUFFERS];
        end
    end
endgenerate

assign w_wr_en = r_wr_en ;
assign w_start_process = (r_start_process == PRECHARGE_CYCLES-1) ? 1'b1 : 1'b0 ;
assign w_row_done = w_start_process && (r_rd_col_cnt == IMG_SIZE - KERNEL_SIZE);
assign o_window       = r_window;
assign o_window_valid = w_start_process;

endmodule