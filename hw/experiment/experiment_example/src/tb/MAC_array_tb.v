module MAC_array_tb (

);

parameter integer IMG_SIZE      = 32;
parameter integer KERNEL_SIZE   = 3;
parameter integer PIXEL_WIDTH   = 8;
parameter integer KERNEL_COEF_WIDTH = 8;
parameter integer OUT_PIXEL_WIDTH = 16;
parameter integer WINDOW_SIZE   = KERNEL_SIZE*KERNEL_SIZE;
parameter integer WINDOW_WIDTH  = PIXEL_WIDTH*WINDOW_SIZE;
parameter integer K_WINDOW_WIDTH  = KERNEL_COEF_WIDTH*WINDOW_SIZE;

reg clk ;
reg rst_n ;
reg [WINDOW_WIDTH-1:0] i_window ;
reg signed [K_WINDOW_WIDTH-1:0] i_kernel ;
reg i_window_valid ;

wire signed [OUT_PIXEL_WIDTH-1:0] o_conv_pixel ;
wire o_pixel_valid ;

MAC_array #(
    .IMG_SIZE(IMG_SIZE),
    .KERNEL_SIZE(KERNEL_SIZE),
    .PIXEL_WIDTH(PIXEL_WIDTH),
    .KERNEL_COEF_WIDTH(KERNEL_COEF_WIDTH),
    .OUT_PIXEL_WIDTH(OUT_PIXEL_WIDTH),
    .WINDOW_SIZE(WINDOW_SIZE),
    .WINDOW_WIDTH(WINDOW_WIDTH),
    .K_WINDOW_WIDTH(K_WINDOW_WIDTH)
) MAC (
    .clk(clk),
    .rst_n(rst_n),
    .i_window(i_window),
    .i_kernel(i_kernel),
    .i_window_valid(i_window_valid),
    .o_conv_pixel(o_conv_pixel),
    .o_pixel_valid(o_pixel_valid)
);

initial clk = 0;
always #10 clk = ~clk ;

initial begin
    rst_n =  0; 
    i_window = 72'h090807060504030201;
    i_kernel = 72'h090807060504030201;
    i_window_valid=0;
    

    #20;
    rst_n = 1;
    i_window_valid=1;
    #500;
    $stop();
end





endmodule