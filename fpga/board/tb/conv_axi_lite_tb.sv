//------------------------------------------------------------------------------
// Module: conv_axi_lite_tb
//
// Purpose:
//   Self-checking test of the board-demo AXI4-Lite wrapper. It drives
//   conv_axi_lite exactly as the PYNQ driver (fpga/board/pynq/conv_demo.py)
//   does - soft reset, kernels written right to left per row, pixels in
//   PIXELS4 bursts plus single PIXEL writes, STATUS polling, feature window
//   read-back - and compares every feature of every lane with a behavioural
//   model of the datapath (valid correlation, round half up, 16-bit
//   saturation, optional ReLU).
//
//   Frames: random image with an identity kernel (lane 0) and Sobel-X or
//   random kernels; a 4-px checkerboard with Sobel-Y or random kernels; a
//   white frame with the extreme kernels all +127 / all -128.
//
// Configuration comes from board_tb_cfg.vh, written by fpga/scripts/board_sim.tcl.
//------------------------------------------------------------------------------
`timescale 1ns/1ps

`include "board_tb_cfg.vh"

module conv_axi_lite_tb;

   parameter int WINDOW_SIZE = `TB_WINDOW_SIZE;
   parameter int INPUT_SIZE  = `TB_INPUT_SIZE;
   parameter int NUM_KERNELS = `TB_NUM_KERNELS;
   parameter bit ENABLE_RELU = 1'(`TB_ENABLE_RELU);

   localparam int ADDR_WIDTH  = 20;
   localparam int N           = WINDOW_SIZE;
   localparam int W           = INPUT_SIZE;
   localparam int K           = NUM_KERNELS;
   localparam int E           = N * N;
   localparam int OUT         = W - N + 1;
   localparam int IDX_BITS    = $clog2(OUT * OUT);
   localparam int ACCUM_WIDTH = 16 + $clog2(E);
   localparam int DROP        = ACCUM_WIDTH - 16;

   localparam logic [ADDR_WIDTH-1:0] REG_ID           = 'h000;
   localparam logic [ADDR_WIDTH-1:0] REG_GEOMETRY     = 'h004;
   localparam logic [ADDR_WIDTH-1:0] REG_CTRL         = 'h00C;
   localparam logic [ADDR_WIDTH-1:0] REG_STATUS       = 'h010;
   localparam logic [ADDR_WIDTH-1:0] REG_KERNEL_SEL   = 'h014;
   localparam logic [ADDR_WIDTH-1:0] REG_WEIGHT       = 'h018;
   localparam logic [ADDR_WIDTH-1:0] REG_PIXEL        = 'h01C;
   localparam logic [ADDR_WIDTH-1:0] REG_PIXELS4      = 'h020;
   localparam logic [ADDR_WIDTH-1:0] REG_WEIGHT_COUNT = 'h024;
   localparam logic [ADDR_WIDTH-1:0] REG_PIXEL_COUNT  = 'h028;
   localparam logic [ADDR_WIDTH-1:0] REG_OUT_COUNT    = 'h02C;
   localparam logic [ADDR_WIDTH-1:0] REG_LATENCY      = 'h030;
   localparam logic [ADDR_WIDTH-1:0] REG_FRAME_CYCLES = 'h034;
   localparam int                    FEATURE_BASE     = 'h1_0000;

   logic clk = 1'b0;
   logic rst_n;

   always #5 clk = ~clk;

   logic [ADDR_WIDTH-1:0] awaddr;
   logic                  awvalid;
   logic                  awready;
   logic [31:0]           wdata;
   logic [3:0]            wstrb;
   logic                  wvalid;
   logic                  wready;
   logic [1:0]            bresp;
   logic                  bvalid;
   logic [ADDR_WIDTH-1:0] araddr;
   logic                  arvalid;
   logic                  arready;
   logic [31:0]           rdata;
   logic [1:0]            rresp;
   logic                  rvalid;
   logic [3:0]            leds;

   conv_axi_lite #(
      .WINDOW_SIZE (WINDOW_SIZE),
      .INPUT_SIZE  (INPUT_SIZE),
      .NUM_KERNELS (NUM_KERNELS),
      .ENABLE_RELU (ENABLE_RELU),
      .ADDR_WIDTH  (ADDR_WIDTH)
   ) u_dut (
      .clk           (clk),
      .rst_n         (rst_n),
      .s_axi_awaddr  (awaddr),
      .s_axi_awvalid (awvalid),
      .s_axi_awready (awready),
      .s_axi_wdata   (wdata),
      .s_axi_wstrb   (wstrb),
      .s_axi_wvalid  (wvalid),
      .s_axi_wready  (wready),
      .s_axi_bresp   (bresp),
      .s_axi_bvalid  (bvalid),
      .s_axi_bready  (1'b1),
      .s_axi_araddr  (araddr),
      .s_axi_arvalid (arvalid),
      .s_axi_arready (arready),
      .s_axi_rdata   (rdata),
      .s_axi_rresp   (rresp),
      .s_axi_rvalid  (rvalid),
      .s_axi_rready  (1'b1),
      .o_leds        (leds)
   );

   // ---- AXI4-Lite master: drive on the falling edge, sample on the rising edge
   task automatic axi_write(input logic [ADDR_WIDTH-1:0] addr, input logic [31:0] data);
      @(negedge clk);
      awaddr  = addr;
      awvalid = 1'b1;
      wdata   = data;
      wstrb   = 4'hF;
      wvalid  = 1'b1;
      do @(posedge clk); while (!(awready && wready));
      @(negedge clk);
      awvalid = 1'b0;
      wvalid  = 1'b0;
   endtask

   task automatic axi_read(input logic [ADDR_WIDTH-1:0] addr, output logic [31:0] data);
      @(negedge clk);
      araddr  = addr;
      arvalid = 1'b1;
      do @(posedge clk); while (!arready);
      @(negedge clk);
      arvalid = 1'b0;
      do @(posedge clk); while (!rvalid);
      data = rdata;
   endtask

   // ---- behavioural model ---------------------------------------------------------
   int image   [W*W];
   int kernels [K][E];

   function automatic int expected(int k, int r, int c);
      longint acc = 0;
      for (int i = 0; i < N; i++)
         for (int j = 0; j < N; j++)
            acc += longint'(image[(r + i) * W + (c + j)]) * longint'(kernels[k][i * N + j]);
      if (DROP > 0) acc = (acc + (longint'(1) <<< (DROP - 1))) >>> DROP;
      if (acc > 32767)  acc = 32767;
      if (acc < -32768) acc = -32768;
      if (ENABLE_RELU && acc < 0) acc = 0;
      return int'(acc);
   endfunction

   int total_errors = 0;

   task automatic run_frame(string name);
      logic [31:0] v;
      int          errors = 0;
      int          polls  = 0;
      int          p      = 0;

      axi_write(REG_CTRL, 32'd1);
      axi_write(REG_CTRL, 32'd0);

      for (int k = 0; k < K; k++) begin
         axi_write(REG_KERNEL_SEL, 32'(k));
         for (int r = 0; r < N; r++)
            for (int c = N - 1; c >= 0; c--)
               axi_write(REG_WEIGHT, 32'(kernels[k][r * N + c]) & 32'hFF);
      end

      while (p + 4 <= W * W) begin
         axi_write(REG_PIXELS4, {8'(image[p+3]), 8'(image[p+2]), 8'(image[p+1]), 8'(image[p])});
         p += 4;
      end
      while (p < W * W) begin
         axi_write(REG_PIXEL, 32'(image[p]));
         p++;
      end

      do begin
         axi_read(REG_STATUS, v);
         polls++;
      end while (!v[2] && polls < 100000);

      if (!v[2]) begin
         $display("[BOARD] %s: FAIL - frame never completed", name);
         total_errors++;
         return;
      end

      axi_read(REG_OUT_COUNT, v);
      if (v != 32'(OUT * OUT)) begin $display("[BOARD] %s: OUT_COUNT %0d, expected %0d", name, v, OUT * OUT); errors++; end
      axi_read(REG_PIXEL_COUNT, v);
      if (v != 32'(W * W)) begin $display("[BOARD] %s: PIXEL_COUNT %0d, expected %0d", name, v, W * W); errors++; end
      axi_read(REG_WEIGHT_COUNT, v);
      if (v != 32'(K * E)) begin $display("[BOARD] %s: WEIGHT_COUNT %0d, expected %0d", name, v, K * E); errors++; end

      for (int k = 0; k < K; k++)
         for (int i = 0; i < OUT * OUT; i++) begin
            axi_read(ADDR_WIDTH'(FEATURE_BASE + (k << (IDX_BITS + 2)) + 4 * i), v);
            if ($signed(v) != expected(k, i / OUT, i % OUT)) begin
               if (errors < 8)
                  $display("[BOARD] %s: lane %0d feature (%0d,%0d) = %0d, expected %0d",
                           name, k, i / OUT, i % OUT, $signed(v), expected(k, i / OUT, i % OUT));
               errors++;
            end
         end

      axi_read(REG_LATENCY, v);
      $display("[BOARD] %s: %0d features x %0d lane(s), %0d mismatches, latency %0d cycles",
               name, OUT * OUT, K, errors, v);
      total_errors += errors;
   endtask

   // ---- kernels ------------------------------------------------------------------
   function automatic void set_sobel(int k, bit vertical);
      int sobel_x [9] = '{-1, 0, 1, -2, 0, 2, -1, 0, 1};
      int sobel_y [9] = '{-1, -2, -1, 0, 0, 0, 1, 2, 1};
      for (int e = 0; e < E; e++)
         kernels[k][e] = (N == 3) ? (vertical ? sobel_y[e] : sobel_x[e]) : ($urandom_range(0, 255) - 128);
   endfunction

   initial begin
      logic [31:0] v;

      awaddr  = '0;
      awvalid = 1'b0;
      wdata   = '0;
      wstrb   = '0;
      wvalid  = 1'b0;
      araddr  = '0;
      arvalid = 1'b0;
      rst_n   = 1'b0;
      repeat (5) @(posedge clk);
      rst_n = 1'b1;

      axi_read(REG_ID, v);
      if (v != 32'h434E_5631) begin $display("[BOARD] ID register %h", v); total_errors++; end
      axi_read(REG_GEOMETRY, v);
      if (v != {8'(K), 8'(N), 16'(W)}) begin $display("[BOARD] GEOMETRY register %h", v); total_errors++; end

      // Frame 1: random image, identity kernel on lane 0, Sobel-X / random elsewhere.
      for (int i = 0; i < W * W; i++) image[i] = $urandom_range(0, 255);
      for (int k = 0; k < K; k++) set_sobel(k, 1'b0);
      for (int e = 0; e < E; e++) kernels[0][e] = 0;
      kernels[0][(N / 2) * N + N / 2] = 1 << DROP;
      run_frame("random image, identity / Sobel-X");

      // Frame 2: 4-px checkerboard 230/25, Sobel-Y / random.
      for (int i = 0; i < W * W; i++) image[i] = (((i / W) / 4 + (i % W) / 4) % 2 == 0) ? 230 : 25;
      for (int k = 0; k < K; k++) set_sobel(k, 1'b1);
      run_frame("checkerboard, Sobel-Y");

      // Frame 3: white frame with the extreme kernels.
      for (int i = 0; i < W * W; i++) image[i] = 255;
      for (int k = 0; k < K; k++)
         for (int e = 0; e < E; e++) kernels[k][e] = (k % 2 == 0) ? 127 : -128;
      run_frame("white frame, all +127 / all -128");

      if (total_errors == 0) $display("TEST PASSED");
      else                   $display("TEST FAILED: %0d errors", total_errors);
      $finish;
   end

   initial begin
      #200ms;
      $display("TEST FAILED: timeout");
      $finish;
   end

endmodule
