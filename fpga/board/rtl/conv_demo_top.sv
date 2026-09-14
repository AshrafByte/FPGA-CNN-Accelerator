//------------------------------------------------------------------------------
// Module: conv_demo_top
//
// Description:
//   Top level of the PYNQ-Z2 board demo. system_wrapper is the block design
//   built by fpga/scripts/bitstream.tcl: the Zynq processing system, an AXI
//   interconnect and a 100 MHz clock with its synchronized reset, exported as
//   the M_AXI (AXI4-Lite) port. conv_axi_lite answers on that port at
//   0x43C00000 and drives conv_system. The four user LEDs show its status.
//------------------------------------------------------------------------------
module conv_demo_top
   #(
      parameter int WINDOW_SIZE = 3,
      parameter int INPUT_SIZE  = 32,
      parameter int NUM_KERNELS = 1,
      parameter bit ENABLE_RELU = 1'b0
   )(
      inout  wire [14:0] DDR_addr,
      inout  wire [2:0]  DDR_ba,
      inout  wire        DDR_cas_n,
      inout  wire        DDR_ck_n,
      inout  wire        DDR_ck_p,
      inout  wire        DDR_cke,
      inout  wire        DDR_cs_n,
      inout  wire [3:0]  DDR_dm,
      inout  wire [31:0] DDR_dq,
      inout  wire [3:0]  DDR_dqs_n,
      inout  wire [3:0]  DDR_dqs_p,
      inout  wire        DDR_odt,
      inout  wire        DDR_ras_n,
      inout  wire        DDR_reset_n,
      inout  wire        DDR_we_n,
      inout  wire        FIXED_IO_ddr_vrn,
      inout  wire        FIXED_IO_ddr_vrp,
      inout  wire [53:0] FIXED_IO_mio,
      inout  wire        FIXED_IO_ps_clk,
      inout  wire        FIXED_IO_ps_porb,
      inout  wire        FIXED_IO_ps_srstb,

      output logic [3:0] leds
   );

   localparam int ADDR_WIDTH = 20;

   logic        clk;
   logic        rst_n;

   logic [31:0] axi_araddr;
   logic [2:0]  axi_arprot;
   logic        axi_arready;
   logic        axi_arvalid;
   logic [31:0] axi_awaddr;
   logic [2:0]  axi_awprot;
   logic        axi_awready;
   logic        axi_awvalid;
   logic        axi_bready;
   logic [1:0]  axi_bresp;
   logic        axi_bvalid;
   logic [31:0] axi_rdata;
   logic        axi_rready;
   logic [1:0]  axi_rresp;
   logic        axi_rvalid;
   logic [31:0] axi_wdata;
   logic        axi_wready;
   logic [3:0]  axi_wstrb;
   logic        axi_wvalid;

   system_wrapper u_system (
      .DDR_addr          (DDR_addr),
      .DDR_ba            (DDR_ba),
      .DDR_cas_n         (DDR_cas_n),
      .DDR_ck_n          (DDR_ck_n),
      .DDR_ck_p          (DDR_ck_p),
      .DDR_cke           (DDR_cke),
      .DDR_cs_n          (DDR_cs_n),
      .DDR_dm            (DDR_dm),
      .DDR_dq            (DDR_dq),
      .DDR_dqs_n         (DDR_dqs_n),
      .DDR_dqs_p         (DDR_dqs_p),
      .DDR_odt           (DDR_odt),
      .DDR_ras_n         (DDR_ras_n),
      .DDR_reset_n       (DDR_reset_n),
      .DDR_we_n          (DDR_we_n),
      .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn),
      .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp),
      .FIXED_IO_mio      (FIXED_IO_mio),
      .FIXED_IO_ps_clk   (FIXED_IO_ps_clk),
      .FIXED_IO_ps_porb  (FIXED_IO_ps_porb),
      .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb),
      .M_AXI_araddr      (axi_araddr),
      .M_AXI_arprot      (axi_arprot),
      .M_AXI_arready     (axi_arready),
      .M_AXI_arvalid     (axi_arvalid),
      .M_AXI_awaddr      (axi_awaddr),
      .M_AXI_awprot      (axi_awprot),
      .M_AXI_awready     (axi_awready),
      .M_AXI_awvalid     (axi_awvalid),
      .M_AXI_bready      (axi_bready),
      .M_AXI_bresp       (axi_bresp),
      .M_AXI_bvalid      (axi_bvalid),
      .M_AXI_rdata       (axi_rdata),
      .M_AXI_rready      (axi_rready),
      .M_AXI_rresp       (axi_rresp),
      .M_AXI_rvalid      (axi_rvalid),
      .M_AXI_wdata       (axi_wdata),
      .M_AXI_wready      (axi_wready),
      .M_AXI_wstrb       (axi_wstrb),
      .M_AXI_wvalid      (axi_wvalid),
      .clk_100           (clk),
      .rst_n             (rst_n)
   );

   conv_axi_lite #(
      .WINDOW_SIZE (WINDOW_SIZE),
      .INPUT_SIZE  (INPUT_SIZE),
      .NUM_KERNELS (NUM_KERNELS),
      .ENABLE_RELU (ENABLE_RELU),
      .ADDR_WIDTH  (ADDR_WIDTH)
   ) u_conv (
      .clk           (clk),
      .rst_n         (rst_n),
      .s_axi_awaddr  (axi_awaddr[ADDR_WIDTH-1:0]),
      .s_axi_awvalid (axi_awvalid),
      .s_axi_awready (axi_awready),
      .s_axi_wdata   (axi_wdata),
      .s_axi_wstrb   (axi_wstrb),
      .s_axi_wvalid  (axi_wvalid),
      .s_axi_wready  (axi_wready),
      .s_axi_bresp   (axi_bresp),
      .s_axi_bvalid  (axi_bvalid),
      .s_axi_bready  (axi_bready),
      .s_axi_araddr  (axi_araddr[ADDR_WIDTH-1:0]),
      .s_axi_arvalid (axi_arvalid),
      .s_axi_arready (axi_arready),
      .s_axi_rdata   (axi_rdata),
      .s_axi_rresp   (axi_rresp),
      .s_axi_rvalid  (axi_rvalid),
      .s_axi_rready  (axi_rready),
      .o_leds        (leds)
   );

endmodule
