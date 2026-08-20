//------------------------------------------------------------------------------
// Module: conv_controller
//
// Description:
//   Generates BRAM read addresses and a write-enable/streaming strobe for a
//   convolution pipeline, sequencing an initial line-buffer fill phase
//   before continuous streaming of the full image.
//
// Architecture:
//   - Three-state FSM: ST_IDLE, ST_LOAD, ST_COMPUTE.
//   - ST_LOAD streams enough elements to fill LINE_NUM rows of line buffer
//     before handing off to ST_COMPUTE.
//   - ST_COMPUTE streams the remaining elements until the full MEMORY_SIZE
//     has been read.
//
// Data Flow:
//   - i_valid_in starts the sequence from ST_IDLE.
//   - o_raddr increments once per cycle while streaming (ST_LOAD or ST_COMPUTE).
//   - o_write_en pulses alongside o_raddr to indicate the address/data is
//     being actively streamed downstream.
//
// Timing:
//   - State, address, column count, and write-enable are all registered,
//     updated on the rising clock edge.
//   - o_raddr/o_write_en are registered outputs (one cycle behind the
//     combinational next-state/datapath logic).
//
// Assumptions:
//   - i_valid_in is a single-cycle pulse (or held) indicating a frame is
//     ready to be streamed; controller does not re-check mid-stream.
//   - Downstream modules (line buffer, memory) accept one new address/write
//     every cycle while o_write_en is high, with no backpressure.
//
// Parameters:
//   LINE_NUM    : Number of line-buffer rows to fill before compute begins.
//   INPUT_SIZE  : Image row width, used to size the fill phase and column tracking.
//   MEMORY_SIZE : Total number of addressable elements in the frame.
//------------------------------------------------------------------------------
module conv_controller #(
   parameter int LINE_NUM    = 3,
   parameter int INPUT_SIZE  = 32,
   parameter int MEMORY_SIZE = 32**2,

   localparam type addr_t = logic [$clog2(MEMORY_SIZE)-1:0]
)(
   input  logic  clk,
   input  logic  rst_n,
   input  logic  i_valid_in,

   output addr_t o_raddr,
   output logic  o_write_en
);
   localparam int  FILL_LIMIT = INPUT_SIZE * LINE_NUM;
   localparam int  READ_LIMIT = MEMORY_SIZE;
   localparam type col_t      = logic [$clog2(INPUT_SIZE)-1:0];

   typedef enum logic [1:0] { ST_IDLE, ST_LOAD, ST_COMPUTE } state_t;

   state_t r_state, w_state;
   addr_t  r_raddr, w_raddr;
   col_t   r_col_cnt, w_col_cnt;
   logic   r_write_en, w_write_en;
   logic   w_streaming;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) r_state <= ST_IDLE;
      else        r_state <= w_state;
   end

   always_comb begin
      w_state = r_state;
      case (r_state)
         ST_IDLE:    w_state = i_valid_in ? ST_LOAD : ST_IDLE;
         ST_LOAD:    w_state = (r_raddr == addr_t'(FILL_LIMIT-1)) ? ST_COMPUTE : ST_LOAD;
         ST_COMPUTE: w_state = (r_raddr == addr_t'(READ_LIMIT-1)) ? ST_IDLE    : ST_COMPUTE;
         default:    w_state = ST_IDLE;
      endcase
   end

   assign w_streaming = (r_state != ST_IDLE);

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         r_raddr    <= '0;
         r_col_cnt  <= '0;
         r_write_en <= '0;
      end else begin
         r_raddr    <= w_raddr;
         r_col_cnt  <= w_col_cnt;
         r_write_en <= w_write_en;
      end
   end

   always_comb begin
      w_raddr    = r_raddr;
      w_col_cnt  = r_col_cnt;
      w_write_en = 1'b0;

      case (r_state)
         ST_IDLE: begin
            w_raddr   = '0;
            w_col_cnt = '0;
         end
         ST_LOAD, ST_COMPUTE: begin
            w_raddr    = r_raddr + 1'b1;
            w_write_en = 1'b1;
         end
      endcase

      if (w_streaming)
         w_col_cnt = (r_col_cnt == col_t'(INPUT_SIZE-1)) ? '0 : r_col_cnt + 1'b1;
   end

   assign o_raddr    = r_raddr;
   assign o_write_en = r_write_en;

endmodule