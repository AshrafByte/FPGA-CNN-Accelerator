module line_buffer_tb (

);

localparam IMG_SIZE = 32 ;
localparam PIXEL_WIDTH = 8 ;

reg clk;
reg rst_n;
reg i_pixel_valid;
reg [PIXEL_WIDTH-1:0] i_pixel_data ;

wire [PIXEL_WIDTH-1:0] o_pixel_data ;

line_buffer #(
    .IMG_SIZE(IMG_SIZE),
    .PIXEL_WIDTH(PIXEL_WIDTH)
) lb (
    .clk(clk),
    .rst_n(rst_n),
    .i_pixel_valid(i_pixel_valid),
    .i_pixel_data(i_pixel_data),
    .o_pixel_data(o_pixel_data)
);

initial clk = 1'b0;
always #10 clk = ~clk ;

integer i ;

initial begin 
    rst_n = 0 ;
    i_pixel_valid = 0;
    i_pixel_data = 0;
    #10 ; 
    rst_n = 1;
    #10;
    i_pixel_valid = 1;
    for (i=0;i<IMG_SIZE+10;i=i+1) begin
        #20 i_pixel_data = i_pixel_data + 1 ;
    end
    #500;
    $stop();

end
endmodule



