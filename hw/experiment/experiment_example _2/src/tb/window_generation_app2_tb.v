module window_generation_app2_tb (

);

parameter integer IMG_SIZE      = 32 ;
parameter integer KERNEL_SIZE   = 3  ;
parameter integer PIXEL_WIDTH   = 8  ;
parameter integer WINDOW_SIZE   = KERNEL_SIZE*KERNEL_SIZE ;
parameter integer WINDOW_WIDTH  = PIXEL_WIDTH*WINDOW_SIZE ;

reg clk;
reg rst_n; 
reg [PIXEL_WIDTH-1:0] i_pixel_data;
reg i_pixel_valid;

wire [WINDOW_WIDTH-1:0] o_window;
wire o_window_valid;

window_generation_app2 #(
    .IMG_SIZE(IMG_SIZE),
    .KERNEL_SIZE(KERNEL_SIZE),
    .PIXEL_WIDTH(PIXEL_WIDTH),
    .WINDOW_SIZE(WINDOW_SIZE),
    .WINDOW_WIDTH(WINDOW_WIDTH)
) w_g (
    .clk(clk),
    .rst_n(rst_n),
    .i_pixel_data(i_pixel_data),
    .i_pixel_valid(i_pixel_valid),
    .o_window(o_window),
    .o_window_valid(o_window_valid)
);

initial clk = 1'b0 ;
always #10 clk = ~clk ;

integer i ;

initial begin
    rst_n = 0;
    i_pixel_data = 0;
    i_pixel_valid = 0;
    #20;
    rst_n = 1;
    i_pixel_valid = 1;
    for (i=0;i<6*IMG_SIZE;i=i+1) begin
        #20 i_pixel_data = i_pixel_data + 1 ;
    end
    #700 ;
    $stop();

end



endmodule
