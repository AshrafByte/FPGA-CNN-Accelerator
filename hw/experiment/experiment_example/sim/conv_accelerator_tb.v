module conv_accelerator_tb();

parameter integer IMG_SIZE      = 32;
parameter integer KERNEL_SIZE   = 3;
parameter integer PIXEL_WIDTH   = 8;
parameter integer KERNEL_COEF_WIDTH = 8;
parameter integer OUT_PIXEL_WIDTH = 16;
parameter integer WINDOW_SIZE   = KERNEL_SIZE*KERNEL_SIZE;
parameter integer MEM_COEF_DEPTH = $clog2(WINDOW_SIZE);

reg clk;
reg rst_n;
reg [PIXEL_WIDTH-1:0] i_pixel_data ;
reg i_pixel_valid ;

reg signed [KERNEL_COEF_WIDTH-1:0] i_weight ;
reg i_wgt_en ;
reg [MEM_COEF_DEPTH-1:0] i_wgt_address ;

wire signed [OUT_PIXEL_WIDTH-1:0] o_conv_pixel ;
wire o_pixel_valid ;


conv_accelerator #(
    .IMG_SIZE(IMG_SIZE),
    .KERNEL_SIZE(KERNEL_SIZE),
    .PIXEL_WIDTH(PIXEL_WIDTH),
    .KERNEL_COEF_WIDTH(KERNEL_COEF_WIDTH),
    .OUT_PIXEL_WIDTH(OUT_PIXEL_WIDTH),
    .WINDOW_SIZE(WINDOW_SIZE),
    .MEM_COEF_DEPTH(MEM_COEF_DEPTH)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .i_pixel_data(i_pixel_data),
    .i_pixel_valid(i_pixel_valid),
    .i_weight(i_weight),
    .i_wgt_en(i_wgt_en),
    .i_wgt_address(i_wgt_address),
    .o_conv_pixel(o_conv_pixel),
    .o_pixel_valid(o_pixel_valid)
);

initial clk = 0;
always #10 clk = ~clk ;
integer i;
initial begin
    rst_n = 0;
    i_pixel_data = 0;
    i_pixel_valid = 0;
    i_weight =0;
    i_wgt_en =0;
    i_wgt_address=0;
    #20;
    rst_n = 1;
    for (i=0;i<WINDOW_SIZE;i=i+1) begin
        #20;
        i_weight = i+1 ;
        i_wgt_en =1;
        i_wgt_address=i;
    end

    #60;
    i_pixel_valid=1;
    i_pixel_data=1;
    for (i=1;i<6*IMG_SIZE;i=i+1) begin
        #20 i_pixel_data = i+1 ;
    end
    #1000 ;
    $stop();


end
    
endmodule