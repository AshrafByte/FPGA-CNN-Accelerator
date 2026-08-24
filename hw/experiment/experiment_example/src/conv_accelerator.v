module conv_accelerator #(
    parameter integer IMG_SIZE      = 32,
    parameter integer KERNEL_SIZE   = 3,
    parameter integer PIXEL_WIDTH   = 8,
    parameter integer KERNEL_COEF_WIDTH = 8,
    parameter integer OUT_PIXEL_WIDTH = 16,
    parameter integer WINDOW_SIZE   = KERNEL_SIZE*KERNEL_SIZE,
    parameter integer MEM_COEF_DEPTH = $clog2(WINDOW_SIZE)
) (
    input clk,
    input rst_n,
    input [PIXEL_WIDTH-1:0] i_pixel_data, 
    input i_pixel_valid,

    input signed [KERNEL_COEF_WIDTH-1:0] i_weight,
    input i_wgt_en,
    input [MEM_COEF_DEPTH-1:0] i_wgt_address,

    output signed [OUT_PIXEL_WIDTH-1:0] o_conv_pixel,
    output o_pixel_valid
);

parameter integer WINDOW_WIDTH  = PIXEL_WIDTH*WINDOW_SIZE ;
parameter integer K_WINDOW_WIDTH  = KERNEL_COEF_WIDTH*WINDOW_SIZE ;

wire signed [K_WINDOW_WIDTH-1:0] o_kernel ;
wire [WINDOW_WIDTH-1:0] o_window ;
wire o_window_valid ;

kernel_weights #(
    .KERNEL_SIZE(KERNEL_SIZE),
    .KERNEL_COEF_WIDTH(KERNEL_COEF_WIDTH),
    .WINDOW_SIZE(WINDOW_SIZE),
    .K_WINDOW_WIDTH(K_WINDOW_WIDTH)
) kernel_wgts (
    .clk(clk),
    .rst_n(rst_n),
    .i_weight(i_weight),
    .i_wgt_en(i_wgt_en),
    .i_wgt_address(i_wgt_address),
    .o_kernel(o_kernel)
);

window_generation #(
    .IMG_SIZE(IMG_SIZE),
    .KERNEL_SIZE(KERNEL_SIZE),
    .PIXEL_WIDTH(PIXEL_WIDTH),
    .WINDOW_SIZE(WINDOW_SIZE),
    .WINDOW_WIDTH(WINDOW_WIDTH)
) u_w_g (
    .clk(clk),
    .rst_n(rst_n),
    .i_pixel_data(i_pixel_data),
    .i_pixel_valid(i_pixel_valid),
    .o_window(o_window),
    .o_window_valid(o_window_valid)
);

MAC_array #(
    .IMG_SIZE(IMG_SIZE),
    .KERNEL_SIZE(KERNEL_SIZE),
    .PIXEL_WIDTH(PIXEL_WIDTH),
    .KERNEL_COEF_WIDTH(KERNEL_COEF_WIDTH),
    .OUT_PIXEL_WIDTH(OUT_PIXEL_WIDTH),
    .WINDOW_SIZE(WINDOW_SIZE),
    .WINDOW_WIDTH(WINDOW_WIDTH)
) u_mac (
    .clk(clk),
    .rst_n(rst_n),
    .i_window(o_window),
    .i_kernel(o_kernel),
    .i_window_valid(o_window_valid),
    .o_conv_pixel(o_conv_pixel),
    .o_pixel_valid(o_pixel_valid)
);
    
endmodule