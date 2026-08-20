
module line_buffer #(
    parameter IMG_SIZE = 32 ,
    parameter PIXEL_WIDTH = 8
) (
    input clk, 
    input rst_n,
    input i_pixel_valid,
    input [PIXEL_WIDTH-1:0] i_pixel_data,

    output [PIXEL_WIDTH-1:0] o_pixel_data

);

localparam LB_SIZE = PIXEL_WIDTH*IMG_SIZE ;

reg [LB_SIZE-1:0] lb;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lb <= {LB_SIZE{1'b0}};
    end
    else if (i_pixel_valid) begin
        lb <= {lb[LB_SIZE-PIXEL_WIDTH-1:0], i_pixel_data};
    end
end

assign o_pixel_data = lb[LB_SIZE-1 -: PIXEL_WIDTH];
    
endmodule