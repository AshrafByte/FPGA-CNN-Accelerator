//------------------------------------------------------------------------------
// Module: conv_system
//
// Description:
//   Top-level integration of a streaming 2D convolution pipeline: pixel
//   acceptance gating, line buffer, window generator, kernel register, a
//   multiply-accumulate (MAC) stage, round/saturate, an optional ReLU
//   activation, and an output FIFO, wired end to end to produce a smoothed,
//   gap-absorbed output feature stream.
//
//   conv_system holds all three MAC architectures and elaborates exactly one of
//   them, chosen from the kernel size, the kernel count, the flip-flop cost of
//   the DSP chains and the DSP budget of the device:
//
//     MAC_SEL 1  tree         multiplier_array + adder_tree  (experiments/conv_tree)
//     MAC_SEL 2  row chains   mac_row_chain: one DSP chain per (experiments/conv_row_chain)
//                             window row + short fabric tree
//     MAC_SEL 3  single chain mac_single_chain: all WINDOW_SIZE**2 (experiments/conv_single_chain)
//                             DSPs in one PCOUT->PCIN chain
//
//   The datapath is replicated NUM_KERNELS times from the MAC stage onward:
//   the window and the pixel front end are shared, every lane sees the same
//   window on the same cycle with its own weights, so all lanes advance in
//   lockstep and produce feature k of every lane together.
//
// Architecture:
//   - This module has NO knowledge of external memory, addressing, or
//     where i_pixel comes from — it only reacts to i_pixel/i_valid_in as
//     presented, cycle by cycle.
//   - Pixel acceptance (w_pixel_write_en) is a one-cycle-delayed registered
//     mirror of i_valid_in, matching the latency convention every other
//     stage uses.
//   - line_buffer stores only the WINDOW_SIZE-1 rows preceding the row
//     currently streaming in — the current row is consumed live, directly
//     off i_pixel, by window_generator.
//   - kernel_register holds statically-loaded kernel weights.
//   - The MAC stage computes the windowed multiply-accumulate. All three
//     architectures reproduce their input valid pattern exactly, only the
//     latency differs, so everything downstream is architecture-agnostic.
//   - round_saturate narrows the ACCUM_WIDTH sum to FEATURE_WIDTH with
//     round half up; its positive clamp is built only when reachable.
//   - relu_unit clamps negative features to zero when ENABLE_RELU is set.
//   - output_fifo absorbs the row-boundary valid gaps of the MAC output,
//     re-emitting a prefill-gated, continuously draining feature stream.
//
// Frames (continuous streaming, no reset between frames):
//   - A frame starts with its first i_pixel_valid and ends with o_frame_done,
//     a one-cycle pulse that is high together with o_valid on the frame's
//     last feature. The next i_pixel_valid starts the next frame; it may
//     follow the previous frame's last pixel immediately.
//   - line_buffer counts the rows of each frame and refills its banks at the
//     start of the next one; it marks the frame's last window (o_frame_end).
//   - Every stage after the window forwards valid through a fixed number of
//     registers, so that mark is delayed by exactly LAST_DELAY cycles
//     (r_last_pipe) and reaches output_fifo together with the frame's last
//     feature. The FIFO re-arms its prefill after draining it and raises
//     o_last, which is o_frame_done.
//   - rst_n is only needed at power-up or to abandon a partial frame.
//
// Assumptions:
//   - Caller presents i_pixel/i_valid_in in raster order for a
//     WINDOW_SIZE x WINDOW_SIZE convolution over INPUT_SIZE x INPUT_SIZE
//     frames, every pixel of a frame exactly once; i_pixel_valid may drop at
//     any time (stalls).
//   - The kernel load completes before a frame streams; weights are static
//     for the frame (the DSP chains rely on it: weights carry no skew). A new
//     kernel may be loaded between frames, after o_frame_done.
//
// Parameters:
//   PIXEL_WIDTH   : Width of each input pixel and kernel weight.
//   WINDOW_SIZE   : Kernel dimension N (N x N kernel).
//   INPUT_SIZE    : Image row width.
//   FEATURE_WIDTH : Width of each output feature after round/saturate.
//   NUM_KERNELS   : Number of parallel kernel lanes.
//   ENABLE_RELU   : 1 inserts a relu_unit per lane, 0 bypasses it.
//   FIFO_RAM_MODE : output FIFO memory, 0 auto / 1 LUTRAM / 2 BRAM.
//   MAC_ARCH      : 0 = automatic, 1 = tree, 2 = row chains, 3 = single chain.
//------------------------------------------------------------------------------
module conv_system
   #(
      parameter int PIXEL_WIDTH = 8,
      parameter int WINDOW_SIZE = 3,
      parameter int INPUT_SIZE  = 32,
      parameter int FEATURE_WIDTH= 16,
      parameter int NUM_KERNELS = 1,
      parameter bit ENABLE_RELU = 1'b0,
      // Output FIFO memory: 0 = automatic (cheapest in the figure of merit),
      // 1 = force distributed RAM, 2 = force block RAM.
      parameter int FIFO_RAM_MODE = 0,
      // Figure-of-merit points one BRAM tile costs (LUTs + 50*DSPs + 100*BRAMs).
      parameter int FOM_BRAM_COST = 100,
      // Extra power one block RAM adds, in mW (measured ~4-5 mW at 200 MHz).
      parameter int BRAM_POWER_MW = 4,

      // ---- MAC architecture selection (see "automatic MAC selection") ----
      // 0 = automatic, 1 = tree (conv_tree), 2 = row chains (conv_row_chain),
      // 3 = single chain (conv_single_chain). Forcing 2 needs WINDOW_SIZE >= 2.
      parameter int MAC_ARCH          = 0,
      // Largest kernel size built as a single chain (one kernel only).
      parameter int CHAIN_MAX_N       = 3,
      // Largest kernel size built as row chains.
      parameter int ROW_CHAIN_MAX_N   = 8,
      // Largest total DSP count (N^2 * NUM_KERNELS) built as row chains when
      // there is more than one kernel.
      parameter int ROW_CHAIN_MAX_DSP = 180,

      localparam int  WINDOW_ELEMENTS = WINDOW_SIZE ** 2,
      localparam int  PRODUCT_WIDTH   = 2 * PIXEL_WIDTH,
      localparam int  ACCUM_WIDTH     = PRODUCT_WIDTH + $clog2(WINDOW_ELEMENTS),
      localparam type data_t          = logic [PIXEL_WIDTH-1:0],
      localparam type accum_t         = logic signed [ACCUM_WIDTH-1:0],
      localparam type feature_t       = logic signed [FEATURE_WIDTH-1:0],
      localparam type sel_ker_t       = logic [$clog2(NUM_KERNELS):0]
   )(
      input logic clk,
      input logic rst_n,

      input data_t i_data,
      input logic  i_pixel_valid,
      input logic  i_weight_valid,
      input sel_ker_t i_select_kernel,

      output feature_t o_feature [NUM_KERNELS],
      output logic     o_valid,
      output logic     o_frame_done
   );

   localparam int  LINE_NUM  = WINDOW_SIZE;
   localparam type k_data_t  = logic signed [PIXEL_WIDTH-1:0];
   // Largest positive window sum: every pixel at 2^P-1, every weight at
   // 2^(P-1)-1. round_saturate uses it to decide at elaboration whether its
   // positive clamp can ever be reached.
   localparam longint ACCUM_MAX = longint'(WINDOW_ELEMENTS)
                                * ((longint'(1) << PIXEL_WIDTH) - 1)
                                * ((longint'(1) << (PIXEL_WIDTH - 1)) - 1);
   localparam type product_t = logic signed [PRODUCT_WIDTH-1:0];
   localparam int FRAME_FEATURES         = (INPUT_SIZE - WINDOW_SIZE + 1) ** 2;
   localparam int FIFO_DEPTH             = (INPUT_SIZE - WINDOW_SIZE) * (WINDOW_SIZE - 1);
   // A frame smaller than its row-edge gap count (tiny frames, large windows)
   // must still be able to fill the prefill, or it would never drain.
   localparam int FIFO_PREFILL_THRESHOLD = (FIFO_DEPTH < FRAME_FEATURES) ? FIFO_DEPTH
                                                                         : FRAME_FEATURES;

   // ---- automatic MAC selection -------------------------------------------------
   // Every architecture uses one DSP multiply per tap, so the DSP count is
   // WINDOW_SIZE**2 * NUM_KERNELS whichever is built. They differ in LUTs
   // (fabric adders), in flip-flops (tap skew registers) and in how they fail:
   //
   //   single chain : no fabric adders (fewest LUTs). Tap e waits e+1 cycles,
   //                  so the skew costs (P+1)*E*(E+1)/2 flip-flops per kernel,
   //                  E = N^2 (grows as N^4), and the whole chain must fit one
   //                  DSP column.
   //   row chains   : N chains of N DSPs + a fabric tree over N row sums.
   //                  Skew (P+1)*N*N*(N+1)/2 flip-flops per kernel (N^3).
   //   tree         : N^2 separate multipliers + a full fabric adder tree
   //                  (most LUTs), no skew. The only one whose multipliers can
   //                  spill into fabric when the DSPs run out (-max_dsp).
   //
   // Measured, 1 kernel, 250 MHz (runs_k, runs_k2, runs_g):
   //   N   single chain            row chains              tree
   //   3   479 FF  +0.63 ns 127 mW 335 FF  +0.49 ns 127 mW 442 FF  +0.63 ns
   //   5   2742 FF +0.11 ns 170 mW 803 FF  +0.28 ns 150 mW 993 FF  +0.51 ns
   //   7   9971 FF +0.20 ns 282 mW 1398 FF +0.20 ns 203 mW 1799 FF +0.37 ns
   //   9   26775 FF -1.38 ns       2256 FF +0.15 ns        2913 FF +0.26 ns
   //   11  59325 FF -1.56 ns       3299 FF -0.04 ns        4271 FF +0.30 ns
   //   13  NOFIT (115k FF)         4482 FF -0.28 ns        5953 FF +0.14 ns
   //   17  -                       -                       200 DSP + fabric mult.
   // The single chain wins at 3x3 (+243 FF, no power change); at 5x5 its
   // +2250 FF cost ~20 mW and lose to the row chains. The row chains stop
   // closing 250 MHz at 11x11, where the tree takes over.
   //
   // Rule (N = WINDOW_SIZE, K = NUM_KERNELS). The limits sit one step inside
   // the measured boundaries above (row chains closed 250 MHz up to 9x9, the
   // device has 220 DSPs) to keep a margin:
   //
   //   One kernel (K = 1)
   //     N <= CHAIN_MAX_N (3)                          -> single chain (conv_single_chain)
   //     CHAIN_MAX_N < N <= ROW_CHAIN_MAX_N (4..8)     -> row chains   (conv_row_chain)
   //     N > ROW_CHAIN_MAX_N (9+)                      -> tree         (conv_tree)
   //
   //   Multiple kernels (K >= 2), never the single chain
   //     N <= ROW_CHAIN_MAX_N (8) and
   //     N^2 * K <= ROW_CHAIN_MAX_DSP (180)            -> row chains   (conv_row_chain)
   //     otherwise                                     -> tree         (conv_tree)
   //
   // Row chains need N >= 2 (their row-sum tree has log2(N) levels), so a
   // 1x1 multi-kernel build falls to the tree.
   localparam int TOTAL_DSP = WINDOW_ELEMENTS * NUM_KERNELS;

   localparam bit ROW_OK    = (WINDOW_SIZE >= 2) && (WINDOW_SIZE <= ROW_CHAIN_MAX_N);

   localparam int MAC_AUTO  = (NUM_KERNELS == 1)
                              ? ((WINDOW_SIZE <= CHAIN_MAX_N) ? 3
                                 : ROW_OK                     ? 2
                                 :                              1)
                              : ((ROW_OK && (TOTAL_DSP <= ROW_CHAIN_MAX_DSP)) ? 2 : 1);
   localparam int MAC_SEL  = ((MAC_ARCH >= 1) && (MAC_ARCH <= 3)) ? MAC_ARCH : MAC_AUTO;

   // ---- valid latency from the MAC input to the output FIFO ------------------
   // Each figure is the length of that module's valid register chain:
   //   mac_single_chain 2 + N^2, mac_row_chain 2 + N + clog2(N),
   //   multiplier_array 3 + adder_tree clog2(N^2), round_saturate 2, relu_unit 1.
   localparam int MAC_LATENCY = (MAC_SEL == 3) ? 2 + WINDOW_ELEMENTS
                              : (MAC_SEL == 2) ? 2 + WINDOW_SIZE + $clog2(WINDOW_SIZE)
                              :                  3 + $clog2(WINDOW_ELEMENTS);
   localparam int LAST_DELAY  = MAC_LATENCY + 2 + (ENABLE_RELU ? 1 : 0);

   // ---- automatic FIFO memory selection -----------------------------------------
   // Picks the output_fifo memory with the lower figure-of-merit cost,
   // FoM = throughput / (P x (LUTs + 50*DSPs + 100*BRAMs)). Calibrated on
   // routed runs of this FIFO (xc7z020, 16-bit features); see experiments/conv_tree/system/conv_system/src/rtl/conv_system.sv
   // for the derivation. Only a memory that fits one block (<= 36 kbit) is
   // considered.
   localparam int FIFO_RAM_DEPTH     = 1 << $clog2(FIFO_DEPTH + 1);
   localparam int FIFO_ADDR_W        = $clog2(FIFO_RAM_DEPTH);
   localparam int FIFO_BITS          = FIFO_RAM_DEPTH * FEATURE_WIDTH;

   localparam int FIFO_LUTRAM_LUTS   = ((FIFO_RAM_DEPTH <= 64)
                                        ? (3 * FEATURE_WIDTH) / 2
                                        : (FEATURE_WIDTH * FIFO_RAM_DEPTH) / 64
                                          + (3 * FEATURE_WIDTH * FIFO_RAM_DEPTH) / 512)
                                     + 13 + FIFO_RAM_DEPTH / 10;

   localparam int EST_TAPS           = WINDOW_ELEMENTS * NUM_KERNELS;
   localparam int EST_RESOURCE       = 70 * EST_TAPS + 100;
   localparam int EST_POWER_MW       = 105 + (3 * EST_TAPS) / 2;

   localparam int FIFO_BRAM_LUTS     = 2 * FIFO_ADDR_W;
   localparam int FIFO_BRAM_TILE_PTS = (FIFO_BITS <= 18000) ? FOM_BRAM_COST / 2   // RAMB18
                                                            : FOM_BRAM_COST;      // RAMB36
   localparam int FIFO_BRAM_POWER_PTS = (EST_RESOURCE * BRAM_POWER_MW + EST_POWER_MW - 1)
                                        / EST_POWER_MW;
   localparam int FIFO_BRAM_PTS      = FIFO_BRAM_LUTS + FIFO_BRAM_TILE_PTS + FIFO_BRAM_POWER_PTS;

   localparam bit FIFO_AUTO_BRAM     = (FIFO_BITS <= 36000) && (FIFO_LUTRAM_LUTS > FIFO_BRAM_PTS);
   localparam bit FIFO_USE_BRAM      = (FIFO_RAM_MODE == 2) || ((FIFO_RAM_MODE == 0) && FIFO_AUTO_BRAM);

   logic r_pixel_write_en;   // registered in gen_pixel_we (see below)
   logic r_weight_write_en;
   logic w_row_done;
   logic w_rows_ready;
   logic w_window_valid;
   logic w_accum_valid [NUM_KERNELS];
   logic w_feature_valid [NUM_KERNELS];
   logic w_operands_valid;
   logic [NUM_KERNELS-1:0] w_kernel_ready ;
   logic w_all_kernels_ready;
   logic w_o_valid [NUM_KERNELS];
   logic w_post_valid [NUM_KERNELS];
   logic w_frame_end;
   logic w_post_last;
   logic w_o_last [NUM_KERNELS];


   data_t w_rows   [LINE_NUM];
   data_t w_window [WINDOW_ELEMENTS];

   k_data_t w_weights [NUM_KERNELS][WINDOW_ELEMENTS];

   accum_t w_accum [NUM_KERNELS];
   feature_t w_feature [NUM_KERNELS];
   feature_t w_post_feature [NUM_KERNELS];
   data_t r_data;

   genvar i ;

   // synthesis translate_off
   initial begin
      $display("[conv_system] WINDOW_SIZE=%0d NUM_KERNELS=%0d MAC_SEL=%0d (%s)  DSP=%0d  FIFO_BRAM=%0d",
               WINDOW_SIZE, NUM_KERNELS, MAC_SEL,
               (MAC_SEL == 3) ? "single chain" : (MAC_SEL == 2) ? "row chains" : "tree",
               TOTAL_DSP, FIFO_USE_BRAM);
      $display("[conv_system] LAST_DELAY=%0d (frame-end mark)", LAST_DELAY);
   end

   // The frame-end mark must meet a feature; anything else means LAST_DELAY
   // no longer matches the valid chains of the stages it spans.
   always @(posedge clk)
      if (rst_n && w_post_last && !w_post_valid[0])
         $error("[conv_system] frame-end mark without a feature: LAST_DELAY=%0d out of step",
                LAST_DELAY);
   // synthesis translate_on

   assign w_all_kernels_ready = &w_kernel_ready;
   assign w_operands_valid = w_all_kernels_ready && w_window_valid;
   assign o_valid      = w_o_valid[0];
   assign o_frame_done = w_o_last[0];

   always_ff @(posedge clk or negedge rst_n) begin: write_en_register
      if (!rst_n) begin
         r_weight_write_en <= 1'b0;
         r_data <= '0;
      end else begin
         r_weight_write_en <= i_weight_valid;
         r_data <= i_data;
      end
   end: write_en_register

   // Pixel write enable. It drives ~97 loads (line buffer SRL enables, column
   // counter, window generator). With the single chain the DSP column
   // stretches the placement and this net became the critical path at 250 MHz
   // (conv_single_chain: WNS +0.386 -> +0.757 ns with the limit), so only that build asks
   // Vivado to duplicate the register. The other builds keep one register.
   generate
      if (MAC_SEL == 3) begin : gen_pixel_we_fanout
         (* max_fanout = 24 *) logic r_we;

         always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) r_we <= 1'b0;
            else        r_we <= i_pixel_valid;

         assign r_pixel_write_en = r_we;
      end : gen_pixel_we_fanout
      else begin : gen_pixel_we
         logic r_we;

         always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) r_we <= 1'b0;
            else        r_we <= i_pixel_valid;

         assign r_pixel_write_en = r_we;
      end : gen_pixel_we
   endgenerate

   line_buffer #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .LINE_LENGTH(INPUT_SIZE),
      .LINE_NUM (LINE_NUM),
      .FRAME_ROWS (INPUT_SIZE)
   ) u_line_buffer (
      .clk (clk),
      .rst_n (rst_n),

      .i_write_en (r_pixel_write_en),
      .i_pixel (r_data),

      .o_rows (w_rows),
      .o_row_done (w_row_done),
      .o_rows_ready(w_rows_ready),
      .o_frame_end (w_frame_end)
   );

   // ---- frame-end mark --------------------------------------------------------
   // o_frame_end is high on the cycle the frame's last window is validated.
   // Delayed LAST_DELAY cycles it arrives with the frame's last feature at the
   // output FIFO. Reset flip-flops rather than an SRL: no LUTs, and a mark
   // left over from an abandoned frame is cleared by rst_n.
   (* srl_style = "register" *) logic r_last_pipe [LAST_DELAY];

   always_ff @(posedge clk or negedge rst_n) begin: last_pipe
      if (!rst_n) begin
         for (int s = 0; s < LAST_DELAY; s++) r_last_pipe[s] <= 1'b0;
      end else begin
         r_last_pipe[0] <= w_frame_end && w_all_kernels_ready;
         for (int s = 1; s < LAST_DELAY; s++) r_last_pipe[s] <= r_last_pipe[s-1];
      end
   end: last_pipe

   assign w_post_last = r_last_pipe[LAST_DELAY-1];

   window_generator #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .WINDOW_SIZE(WINDOW_SIZE)
   ) u_window_generator (
      .clk (clk),
      .rst_n (rst_n),

      .i_write_en (r_pixel_write_en),
      .i_row_done (w_row_done),
      .i_rows_ready(w_rows_ready),
      .i_rows (w_rows),

      .o_window (w_window),
      .o_valid (w_window_valid)
   );

   generate
      for(i=0;i<NUM_KERNELS;i++) begin : gen_kerenl_register
         logic w_kernel_en[NUM_KERNELS] ;
         assign w_kernel_en[i] = r_weight_write_en&&(i_select_kernel==i);

         kernel_register #(
            .PIXEL_WIDTH(PIXEL_WIDTH),
            .WINDOW_SIZE(WINDOW_SIZE)
         ) u_kernel_register (
            .clk (clk),
            .rst_n (rst_n),

            .i_write_en (w_kernel_en[i]),
            .i_weight(r_data),

            .o_weights (w_weights[i]),
            .o_ready(w_kernel_ready[i])
         );
      end : gen_kerenl_register
   endgenerate

   // ---- multiply-accumulate: exactly one architecture is elaborated ----------
   generate
      for(i=0;i<NUM_KERNELS;i++) begin : gen_mac
         if (MAC_SEL == 3) begin : gen_single_chain
            mac_single_chain #(
               .PIXEL_WIDTH(PIXEL_WIDTH),
               .WINDOW_SIZE(WINDOW_SIZE)
            ) u_mac (
               .clk (clk),
               .rst_n (rst_n),

               .i_valid (w_operands_valid),
               .i_pixels (w_window),
               .i_weights (w_weights[i]),

               .o_sum (w_accum[i]),
               .o_valid(w_accum_valid[i])
            );
         end : gen_single_chain
         else if (MAC_SEL == 2) begin : gen_row_chain
            mac_row_chain #(
               .PIXEL_WIDTH(PIXEL_WIDTH),
               .WINDOW_SIZE(WINDOW_SIZE)
            ) u_mac (
               .clk (clk),
               .rst_n (rst_n),

               .i_valid (w_operands_valid),
               .i_pixels (w_window),
               .i_weights (w_weights[i]),

               .o_sum (w_accum[i]),
               .o_valid(w_accum_valid[i])
            );
         end : gen_row_chain
         else begin : gen_tree
            product_t w_products [WINDOW_ELEMENTS];
            logic     w_products_valid;

            multiplier_array #(
               .PIXEL_WIDTH(PIXEL_WIDTH),
               .INPUTS_NUM (WINDOW_ELEMENTS)
            ) u_multiplier_array (
               .clk (clk),
               .rst_n (rst_n),

               .i_valid (w_operands_valid),
               .i_pixels (w_window),
               .i_weights (w_weights[i]),

               .o_products (w_products),
               .o_valid(w_products_valid)
            );

            adder_tree #(
               .PRODUCT_WIDTH(PRODUCT_WIDTH),
               .NUM_INPUTS (WINDOW_ELEMENTS)
            ) u_adder_tree (
               .clk (clk),
               .rst_n (rst_n),

               .i_valid (w_products_valid),
               .i_products (w_products),

               .o_sum (w_accum[i]),
               .o_valid(w_accum_valid[i])
            );
         end : gen_tree
      end : gen_mac
   endgenerate

   generate
      for(i=0;i<NUM_KERNELS;i++) begin : gen_round_sat
         round_saturate #(
            .IN_WIDTH(ACCUM_WIDTH),
            .OUT_WIDTH(FEATURE_WIDTH),
            .IN_MAX(ACCUM_MAX)
         ) u_round_saturate (
            .clk(clk),
            .rst_n(rst_n),

            .i_valid(w_accum_valid[i]),
            .i_data(w_accum[i]),

            .o_valid(w_feature_valid[i]),
            .o_data(w_feature[i])
         );
      end : gen_round_sat
   endgenerate

   generate
      for(i=0;i<NUM_KERNELS;i++) begin : gen_post
         if (ENABLE_RELU) begin : gen_relu
            relu_unit #(
               .FEATURE_WIDTH(FEATURE_WIDTH)
            ) u_relu_unit (
               .clk (clk),
               .rst_n (rst_n),

               .i_valid (w_feature_valid[i]),
               .i_feature (w_feature[i]),

               .o_valid (w_post_valid[i]),
               .o_feature (w_post_feature[i])
            );
         end : gen_relu
         else begin : gen_bypass
            assign w_post_valid[i]   = w_feature_valid[i];
            assign w_post_feature[i] = w_feature[i];
         end : gen_bypass
      end : gen_post
   endgenerate

   generate
      for(i=0;i<NUM_KERNELS;i++) begin : gen_output_fifo
         output_fifo #(
            .PIXEL_WIDTH (FEATURE_WIDTH),
            .DEPTH (FIFO_DEPTH),
            .PREFILL_THRESHOLD(FIFO_PREFILL_THRESHOLD),
            .USE_BRAM (FIFO_USE_BRAM)
         ) u_output_fifo (
            .clk (clk),
            .rst_n (rst_n),

            .i_valid (w_post_valid[i]),
            .i_data (w_post_feature[i]),
            .i_last (w_post_last),

            .o_data (o_feature[i]),
            .o_valid(w_o_valid[i]),
            .o_last (w_o_last[i])
         );
      end : gen_output_fifo
   endgenerate

endmodule
