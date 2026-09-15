//------------------------------------------------------------------------------
// Module: conv_axi_lite
//
// Description:
//   AXI4-Lite front end that lets the Zynq processing system drive conv_system
//   on the PYNQ-Z2 board demo. The host writes the kernels and the pixels as
//   register writes, the wrapper feeds them to conv_system one per clock cycle
//   and stores every output feature in a per-lane result memory the host reads
//   back through a memory window.
//
// Register map (offsets from the base address, 32-bit registers):
//   0x000 ID            RO  0x434E5631 ("CNV1")
//   0x004 GEOMETRY      RO  [15:0] INPUT_SIZE  [23:16] WINDOW_SIZE  [31:24] NUM_KERNELS
//   0x008 FORMAT        RO  [7:0] feature bits  [15:8] IDX_BITS  [16] ENABLE_RELU
//   0x00C CTRL          RW  [0] soft reset of the accelerator (level, write 1 then 0)
//   0x010 STATUS        RO  [0] all weights loaded  [1] streaming  [2] frame done
//   0x014 KERNEL_SEL    RW  lane the next WEIGHT writes load
//   0x018 WEIGHT        WO  [7:0] next weight (int8), in hardware tap order
//   0x01C PIXEL         WO  [7:0] next pixel
//   0x020 PIXELS4       WO  four pixels in one write, byte 0 first
//   0x024 WEIGHT_COUNT  RO  weights accepted since reset
//   0x028 PIXEL_COUNT   RO  pixels accepted for the current frame
//   0x02C OUT_COUNT     RO  features captured for the current frame
//   0x030 LATENCY       RO  clock cycles from the frame's first pixel to its first feature
//   0x034 FRAME_CYCLES  RO  clock cycles from the frame's first pixel to its last feature
//   0x038 FRAME_COUNT   RO  frames completed since reset (conv_system o_frame_done pulses)
//   0x10000 + (k << (IDX_BITS + 2)) + 4*i   RO  feature i of lane k, sign-extended
//
// Protocol: CTRL = 1, CTRL = 0 once; for every lane k write KERNEL_SEL = k and
// the N*N weights. Then, for every frame: write the W*W pixels (PIXELS4 and
// PIXEL); wait for STATUS[2]; read OUT_SIZE*OUT_SIZE features per lane. No reset
// between frames: STATUS[2] is set by conv_system's o_frame_done and held until
// the next frame's first pixel, which also clears the per-frame counters. A new
// kernel may be written between frames, after STATUS[2]. The result memory holds
// one frame, so read it before sending the next one.
//
// Tap order: a new window column enters at column 0, so each kernel row is
// written right to left (the same order as sw/conv_lab hardware.contract.pack_kernel).
//
// Parameters:
//   WINDOW_SIZE, INPUT_SIZE, NUM_KERNELS, ENABLE_RELU : passed to conv_system.
//   ADDR_WIDTH : AXI address bits decoded (the block design maps 1 MB).
//------------------------------------------------------------------------------
module conv_axi_lite
   #(
      parameter int WINDOW_SIZE = 3,
      parameter int INPUT_SIZE  = 32,
      parameter int NUM_KERNELS = 1,
      parameter bit ENABLE_RELU = 1'b0,
      parameter int ADDR_WIDTH  = 20
   )(
      input  logic                  clk,
      input  logic                  rst_n,

      input  logic [ADDR_WIDTH-1:0] s_axi_awaddr,
      input  logic                  s_axi_awvalid,
      output logic                  s_axi_awready,
      input  logic [31:0]           s_axi_wdata,
      input  logic [3:0]            s_axi_wstrb,
      input  logic                  s_axi_wvalid,
      output logic                  s_axi_wready,
      output logic [1:0]            s_axi_bresp,
      output logic                  s_axi_bvalid,
      input  logic                  s_axi_bready,

      input  logic [ADDR_WIDTH-1:0] s_axi_araddr,
      input  logic                  s_axi_arvalid,
      output logic                  s_axi_arready,
      output logic [31:0]           s_axi_rdata,
      output logic [1:0]            s_axi_rresp,
      output logic                  s_axi_rvalid,
      input  logic                  s_axi_rready,

      output logic [3:0]            o_leds
   );

   localparam int PIXEL_WIDTH   = 8;
   localparam int FEATURE_WIDTH = 16;
   localparam int OUT_SIZE      = INPUT_SIZE - WINDOW_SIZE + 1;
   localparam int OUT_PIXELS    = OUT_SIZE * OUT_SIZE;
   localparam int WEIGHTS_TOTAL = WINDOW_SIZE * WINDOW_SIZE * NUM_KERNELS;
   localparam int IDX_BITS      = $clog2(OUT_PIXELS);
   localparam int LANE_BITS     = (NUM_KERNELS > 1) ? $clog2(NUM_KERNELS) : 1;
   localparam int SEL_BITS      = $clog2(NUM_KERNELS) + 1;

   localparam logic [31:0] CORE_ID      = 32'h434E_5631;
   localparam int          FEATURE_BASE = 32'h0001_0000;

   localparam logic [11:0] REG_ID           = 12'h000;
   localparam logic [11:0] REG_GEOMETRY     = 12'h004;
   localparam logic [11:0] REG_FORMAT       = 12'h008;
   localparam logic [11:0] REG_CTRL         = 12'h00C;
   localparam logic [11:0] REG_STATUS       = 12'h010;
   localparam logic [11:0] REG_KERNEL_SEL   = 12'h014;
   localparam logic [11:0] REG_WEIGHT       = 12'h018;
   localparam logic [11:0] REG_PIXEL        = 12'h01C;
   localparam logic [11:0] REG_PIXELS4      = 12'h020;
   localparam logic [11:0] REG_WEIGHT_COUNT = 12'h024;
   localparam logic [11:0] REG_PIXEL_COUNT  = 12'h028;
   localparam logic [11:0] REG_OUT_COUNT    = 12'h02C;
   localparam logic [11:0] REG_LATENCY      = 12'h030;
   localparam logic [11:0] REG_FRAME_CYCLES = 12'h034;
   localparam logic [11:0] REG_FRAME_COUNT  = 12'h038;

   typedef logic        [PIXEL_WIDTH-1:0]   data_t;
   typedef logic signed [FEATURE_WIDTH-1:0] feature_t;

   // synthesis translate_off
   initial begin
      if (FEATURE_BASE + (NUM_KERNELS << (IDX_BITS + 2)) > (1 << ADDR_WIDTH))
         $error("[conv_axi_lite] %0d lanes of %0d features do not fit %0d address bits",
                NUM_KERNELS, OUT_PIXELS, ADDR_WIDTH);
   end
   // synthesis translate_on

   // ---- accelerator reset ----------------------------------------------------
   logic r_soft_reset;
   logic r_core_rst_n;

   always_ff @(posedge clk or negedge rst_n) begin : core_reset
      if (!rst_n) r_core_rst_n <= 1'b0;
      else        r_core_rst_n <= !r_soft_reset;
   end : core_reset

   // ---- write channel and input feed ----------------------------------------------
   // A WEIGHT, PIXEL or PIXELS4 write queues one to four bytes; they reach
   // conv_system one per cycle. Writes wait while the queue is not empty.
   data_t                r_feed [4];
   logic [2:0]           r_feed_left;
   logic                 r_feed_weight;
   logic [LANE_BITS-1:0] r_kernel_sel;

   data_t                r_core_data;
   logic                 r_core_pixel_valid;
   logic                 r_core_weight_valid;
   logic [SEL_BITS-1:0]  r_core_select;

   logic                 w_wr_fire;
   logic                 w_wr_reg;
   logic [11:0]          w_wr_off;

   assign w_wr_fire     = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid && (r_feed_left == 3'd0);
   assign s_axi_awready = w_wr_fire;
   assign s_axi_wready  = w_wr_fire;
   assign s_axi_bresp   = 2'b00;
   assign w_wr_reg      = (s_axi_awaddr[ADDR_WIDTH-1:12] == '0);
   assign w_wr_off      = {s_axi_awaddr[11:2], 2'b00};

   always_ff @(posedge clk or negedge rst_n) begin : write_path
      if (!rst_n) begin
         s_axi_bvalid        <= 1'b0;
         r_soft_reset        <= 1'b0;
         r_kernel_sel        <= '0;
         r_feed_left         <= 3'd0;
         r_feed_weight       <= 1'b0;
         r_core_data         <= '0;
         r_core_pixel_valid  <= 1'b0;
         r_core_weight_valid <= 1'b0;
         r_core_select       <= '0;
         for (int b = 0; b < 4; b++) r_feed[b] <= '0;
      end else begin
         if (w_wr_fire)         s_axi_bvalid <= 1'b1;
         else if (s_axi_bready) s_axi_bvalid <= 1'b0;

         r_core_pixel_valid  <= 1'b0;
         r_core_weight_valid <= 1'b0;
         if (r_feed_left != 3'd0) begin
            r_core_data         <= r_feed[0];
            r_core_pixel_valid  <= !r_feed_weight;
            r_core_weight_valid <= r_feed_weight;
            r_core_select       <= (NUM_KERNELS > 1) ? SEL_BITS'(r_kernel_sel) : '0;
            r_feed[0]           <= r_feed[1];
            r_feed[1]           <= r_feed[2];
            r_feed[2]           <= r_feed[3];
            r_feed_left         <= r_feed_left - 3'd1;
         end

         if (w_wr_fire && w_wr_reg) begin
            case (w_wr_off)
               REG_CTRL:       r_soft_reset <= s_axi_wdata[0];
               REG_KERNEL_SEL: r_kernel_sel <= s_axi_wdata[LANE_BITS-1:0];
               REG_WEIGHT: begin
                  r_feed[0]     <= s_axi_wdata[7:0];
                  r_feed_left   <= 3'd1;
                  r_feed_weight <= 1'b1;
               end
               REG_PIXEL: begin
                  r_feed[0]     <= s_axi_wdata[7:0];
                  r_feed_left   <= 3'd1;
                  r_feed_weight <= 1'b0;
               end
               REG_PIXELS4: begin
                  r_feed[0]     <= s_axi_wdata[7:0];
                  r_feed[1]     <= s_axi_wdata[15:8];
                  r_feed[2]     <= s_axi_wdata[23:16];
                  r_feed[3]     <= s_axi_wdata[31:24];
                  r_feed_left   <= 3'd4;
                  r_feed_weight <= 1'b0;
               end
               default: ;
            endcase
         end
      end
   end : write_path

   // ---- accelerator --------------------------------------------------------------
   feature_t w_core_feature [NUM_KERNELS];
   logic     w_core_valid;
   logic     w_core_frame_done;

   conv_system #(
      .PIXEL_WIDTH   (PIXEL_WIDTH),
      .WINDOW_SIZE   (WINDOW_SIZE),
      .INPUT_SIZE    (INPUT_SIZE),
      .FEATURE_WIDTH (FEATURE_WIDTH),
      .NUM_KERNELS   (NUM_KERNELS),
      .ENABLE_RELU   (ENABLE_RELU)
   ) u_conv_system (
      .clk             (clk),
      .rst_n           (r_core_rst_n),
      .i_data          (r_core_data),
      .i_pixel_valid   (r_core_pixel_valid),
      .i_weight_valid  (r_core_weight_valid),
      .i_select_kernel (r_core_select),
      .o_feature       (w_core_feature),
      .o_valid         (w_core_valid),
      .o_frame_done    (w_core_frame_done)
   );

   // ---- counters -------------------------------------------------------------------
   // r_done follows conv_system: set by o_frame_done (the frame's last feature,
   // which is still captured), cleared by the next frame's first pixel together
   // with the per-frame counters. The accelerator itself is not reset.
   logic [31:0]       r_weight_count;
   logic [31:0]       r_pixel_count;
   logic [31:0]       r_cycle;
   logic [31:0]       r_latency;
   logic [31:0]       r_frame_cycles;
   logic [31:0]       r_frame_count;
   logic [IDX_BITS:0] r_out_count;
   logic              r_started;
   logic              r_done;
   logic              w_new_frame;
   logic              w_capture;

   assign w_new_frame = r_core_pixel_valid && r_done;
   assign w_capture   = w_core_valid && !r_done;

   always_ff @(posedge clk or negedge rst_n) begin : counters
      if (!rst_n) begin
         r_weight_count <= '0;
         r_pixel_count  <= '0;
         r_cycle        <= '0;
         r_latency      <= '0;
         r_frame_cycles <= '0;
         r_frame_count  <= '0;
         r_out_count    <= '0;
         r_started      <= 1'b0;
         r_done         <= 1'b0;
      end else if (!r_core_rst_n) begin
         r_weight_count <= '0;
         r_pixel_count  <= '0;
         r_cycle        <= '0;
         r_latency      <= '0;
         r_frame_cycles <= '0;
         r_frame_count  <= '0;
         r_out_count    <= '0;
         r_started      <= 1'b0;
         r_done         <= 1'b0;
      end else begin
         if (r_core_weight_valid) r_weight_count <= r_weight_count + 32'd1;
         if (r_core_pixel_valid) begin
            r_pixel_count <= w_new_frame ? 32'd1 : r_pixel_count + 32'd1;
            r_started     <= 1'b1;
         end

         if (w_new_frame) begin
            r_done         <= 1'b0;
            r_out_count    <= '0;
            r_cycle        <= '0;
            r_latency      <= '0;
            r_frame_cycles <= '0;
         end else begin
            if (r_started && !r_done) r_cycle <= r_cycle + 32'd1;
            if (w_capture) begin
               r_out_count <= r_out_count + 1'b1;
               if (r_out_count == '0) r_latency      <= r_cycle;
               if (w_core_frame_done) r_frame_cycles <= r_cycle;
            end
            if (w_core_frame_done) begin
               r_done        <= 1'b1;
               r_frame_count <= r_frame_count + 32'd1;
            end
         end
      end
   end : counters

   // ---- result memories: one block RAM per lane -----------------------------------
   logic [ADDR_WIDTH-1:0]    r_rd_addr;
   logic [ADDR_WIDTH-1:0]    w_rd_local;
   logic [IDX_BITS-1:0]      w_rd_idx;
   logic [FEATURE_WIDTH-1:0] w_rd_q [NUM_KERNELS];

   assign w_rd_local = r_rd_addr - ADDR_WIDTH'(FEATURE_BASE);
   assign w_rd_idx   = w_rd_local[IDX_BITS+1:2];

   generate
      for (genvar k = 0; k < NUM_KERNELS; k++) begin : gen_result_ram
         (* ram_style = "block" *) logic [FEATURE_WIDTH-1:0] r_mem [OUT_PIXELS];
         logic [FEATURE_WIDTH-1:0] r_q;

         always_ff @(posedge clk) begin : result_ram
            if (w_capture) r_mem[r_out_count[IDX_BITS-1:0]] <= w_core_feature[k];
            r_q <= r_mem[w_rd_idx];
         end : result_ram

         assign w_rd_q[k] = r_q;
      end : gen_result_ram
   endgenerate

   // ---- read channel -------------------------------------------------------------------
   // Handshake, one cycle for the result RAM, then the response.
   logic [1:0]  r_rd_stage;
   logic [31:0] w_reg_word;
   logic [31:0] w_feature_word;
   logic        w_rd_is_feature;
   logic [ADDR_WIDTH-1:0] w_rd_lane;

   assign s_axi_arready  = (r_rd_stage == 2'd0) && !s_axi_rvalid;
   assign s_axi_rresp    = 2'b00;
   assign w_rd_is_feature = (r_rd_addr >= ADDR_WIDTH'(FEATURE_BASE));
   assign w_rd_lane       = w_rd_local >> (IDX_BITS + 2);

   always_comb begin : feature_word
      w_feature_word = '0;
      if ((w_rd_lane < ADDR_WIDTH'(NUM_KERNELS)) && (int'(w_rd_idx) < OUT_PIXELS)) begin
         w_feature_word = {{(32-FEATURE_WIDTH){w_rd_q[w_rd_lane[LANE_BITS-1:0]][FEATURE_WIDTH-1]}},
                           w_rd_q[w_rd_lane[LANE_BITS-1:0]]};
      end
   end : feature_word

   always_comb begin : register_word
      w_reg_word = '0;
      if (r_rd_addr[ADDR_WIDTH-1:12] == '0) begin
         case ({r_rd_addr[11:2], 2'b00})
            REG_ID:           w_reg_word = CORE_ID;
            REG_GEOMETRY:     w_reg_word = {8'(NUM_KERNELS), 8'(WINDOW_SIZE), 16'(INPUT_SIZE)};
            REG_FORMAT:       w_reg_word = {15'd0, ENABLE_RELU, 8'(IDX_BITS), 8'(FEATURE_WIDTH)};
            REG_CTRL:         w_reg_word = {31'd0, r_soft_reset};
            REG_STATUS:       w_reg_word = {29'd0, r_done,
                                            r_started && !r_done,
                                            r_weight_count >= 32'(WEIGHTS_TOTAL)};
            REG_KERNEL_SEL:   w_reg_word = 32'(r_kernel_sel);
            REG_WEIGHT_COUNT: w_reg_word = r_weight_count;
            REG_PIXEL_COUNT:  w_reg_word = r_pixel_count;
            REG_OUT_COUNT:    w_reg_word = 32'(r_out_count);
            REG_LATENCY:      w_reg_word = r_latency;
            REG_FRAME_CYCLES: w_reg_word = r_frame_cycles;
            REG_FRAME_COUNT:  w_reg_word = r_frame_count;
            default:          w_reg_word = '0;
         endcase
      end
   end : register_word

   always_ff @(posedge clk or negedge rst_n) begin : read_path
      if (!rst_n) begin
         s_axi_rvalid <= 1'b0;
         s_axi_rdata  <= '0;
         r_rd_stage   <= 2'd0;
         r_rd_addr    <= '0;
      end else begin
         if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
         case (r_rd_stage)
            2'd0: if (s_axi_arvalid && s_axi_arready) begin
                     r_rd_addr  <= s_axi_araddr;
                     r_rd_stage <= 2'd1;
                  end
            2'd1: r_rd_stage <= 2'd2;
            default: begin
               s_axi_rvalid <= 1'b1;
               s_axi_rdata  <= w_rd_is_feature ? w_feature_word : w_reg_word;
               r_rd_stage   <= 2'd0;
            end
         endcase
      end
   end : read_path

   // ---- board LEDs: LD0 weights loaded, LD1 streaming, LD2 frame done, LD3 heartbeat
   logic [25:0] r_heartbeat;

   always_ff @(posedge clk or negedge rst_n) begin : heartbeat
      if (!rst_n) r_heartbeat <= '0;
      else        r_heartbeat <= r_heartbeat + 26'd1;
   end : heartbeat

   assign o_leds = {r_heartbeat[25], r_done, r_started && !r_done,
                    r_weight_count >= 32'(WEIGHTS_TOTAL)};

endmodule
