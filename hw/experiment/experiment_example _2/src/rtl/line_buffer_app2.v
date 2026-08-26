module line_buffer_app2 #(
    parameter integer IMG_SIZE = 32 ,
    parameter integer KERNEL_SIZE = 3,
    parameter integer PIXEL_WIDTH = 8,
    parameter integer LB_DEPTH = $clog2(IMG_SIZE)
) (
    input clk,
    input rst_n,
    input i_wr_en,
    input [PIXEL_WIDTH-1:0] i_pixel_data,
    input [LB_DEPTH-1:0] i_wr_address,
    input [LB_DEPTH-1:0] i_rd_address,

    output [KERNEL_SIZE*PIXEL_WIDTH-1:0] o_pixel_data
);
localparam LB_SIZE = PIXEL_WIDTH*IMG_SIZE ;

reg [LB_SIZE-1:0] lb ;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lb <= {LB_SIZE{1'b0}};
    end
    else if (i_wr_en) begin
        lb[i_wr_address*PIXEL_WIDTH +: PIXEL_WIDTH] <= i_pixel_data;
    end
end

assign o_pixel_data = lb[i_rd_address*PIXEL_WIDTH +: PIXEL_WIDTH*KERNEL_SIZE];
     
endmodule