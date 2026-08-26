module kernel_weights #(
    parameter integer KERNEL_SIZE   = 3, 
    parameter integer KERNEL_COEF_WIDTH = 8,
    parameter integer WINDOW_SIZE   = KERNEL_SIZE*KERNEL_SIZE,
    parameter integer K_WINDOW_WIDTH  = KERNEL_COEF_WIDTH*WINDOW_SIZE,
    parameter integer MEM_COEF_DEPTH = $clog2(WINDOW_SIZE)
) (
    input clk, 
    input rst_n,
    input signed [KERNEL_COEF_WIDTH-1:0] i_weight ,
    input i_wgt_en,
    input [MEM_COEF_DEPTH-1:0] i_wgt_address,
    
    output [K_WINDOW_WIDTH-1:0] o_kernel
);

reg signed [KERNEL_COEF_WIDTH-1:0] weights [0:WINDOW_SIZE-1] ;

always @(posedge clk) begin
    if(i_wgt_en) begin
        weights[i_wgt_address] <= i_weight ;
    end
end

genvar i ;
generate
    for(i=0;i<WINDOW_SIZE;i=i+1)
        assign o_kernel[i*KERNEL_COEF_WIDTH +:KERNEL_COEF_WIDTH] = weights[i] ;
endgenerate
    
endmodule