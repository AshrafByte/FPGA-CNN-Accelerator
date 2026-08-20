module window_generation #(
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
localparam integer COUNT_WIDTH = $clog2(IMG_SIZE); 


wire    [PIXEL_WIDTH-1:0]   lb_io       [0:KERNEL_SIZE-1]                   ;
reg     [PIXEL_WIDTH-1:0]   r_window    [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1]  ;

reg     [COUNT_WIDTH-1:0]    r_col_cnt;
reg     [COUNT_WIDTH-1:0]    r_row_cnt;
reg                          r_window_valid;

assign lb_io[0]     = i_pixel_data  ;

genvar i;
generate
    for(i=0;i<KERNEL_SIZE-1;i=i+1) begin
        line_buffer #(
            .IMG_SIZE(IMG_SIZE),
            .PIXEL_WIDTH(PIXEL_WIDTH)
        ) u_lb (
            .clk(clk),
            .rst_n(rst_n),
            .i_pixel_valid(i_pixel_valid),
            .i_pixel_data(lb_io[i]),
            .o_pixel_data(lb_io[i+1])
        );
    end
endgenerate

genvar j,k;
generate
for (j=0;j<KERNEL_SIZE;j=j+1) begin
    for (k=0;k<KERNEL_SIZE;k=k+1) begin
        localparam integer BIT_OFFSET = (j * KERNEL_SIZE + k) * PIXEL_WIDTH;
        if (k == 0) begin : first_tap
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    r_window[j][k] <= 0;
                end
                else if (i_pixel_valid) begin 
                    r_window[j][k] <= lb_io[j];
                end
            end
        end else begin : shift_tap
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    r_window[j][k] <= 0;
                end
                else if (i_pixel_valid) begin
                    r_window[j][k] <= r_window[j][k-1];
                end
            end
        end

        assign o_window[WINDOW_WIDTH - 1 - BIT_OFFSET -: PIXEL_WIDTH] = r_window[j][k];
    end
end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_col_cnt      <= 0;
        r_row_cnt      <= 0;
        r_window_valid <= 1'b0;
    end
    else if (i_pixel_valid) begin
        if (r_col_cnt == IMG_SIZE - 1) begin
            r_col_cnt <= 0;

            if (r_row_cnt == IMG_SIZE - 1) begin
                r_row_cnt <= 0;
            end else begin
                r_row_cnt <= r_row_cnt + 1'b1;
            end
        end else begin
            r_col_cnt <= r_col_cnt + 1'b1;
        end
        if ((r_row_cnt >= KERNEL_SIZE - 1) && (r_col_cnt >= KERNEL_SIZE - 1)) begin
            r_window_valid <= 1'b1;
        end else begin
            r_window_valid <= 1'b0;
        end
    end else begin
        r_window_valid <= 1'b0;
    end
end

assign o_window_valid = r_window_valid;

    
endmodule