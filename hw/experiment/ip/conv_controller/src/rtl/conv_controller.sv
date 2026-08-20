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

   state_t q_state, d_state;
   addr_t  q_raddr, d_raddr;
   col_t   q_col_cnt, d_col_cnt;
   logic   q_write_en, d_write_en;
   logic   w_streaming;

   always_ff @(posedge clk or negedge rst_n) begin : state_register
      if (!rst_n) q_state <= ST_IDLE;
      else        q_state <= d_state;
   end : state_register

   always_comb begin : state_next_logic
      d_state = q_state;
      case (q_state)
         ST_IDLE:    d_state = i_valid_in ? ST_LOAD : ST_IDLE;
         ST_LOAD:    d_state = (q_raddr == addr_t'(FILL_LIMIT-1)) ? ST_COMPUTE : ST_LOAD;
         ST_COMPUTE: d_state = (q_raddr == addr_t'(READ_LIMIT-1)) ? ST_IDLE    : ST_COMPUTE;
         default:    d_state = ST_IDLE;
      endcase
   end : state_next_logic

   assign w_streaming = (q_state != ST_IDLE);

   always_ff @(posedge clk or negedge rst_n) begin : datapath_registers
      if (!rst_n) begin : reset_datapath_registers
         q_raddr    <= '0;
         q_col_cnt  <= '0;
         q_write_en <= '0;
      end else begin : datapath_register_update
         q_raddr    <= d_raddr;
         q_col_cnt  <= d_col_cnt;
         q_write_en <= d_write_en;
      end
   end : datapath_registers

   always_comb begin : datapath_next_logic
      d_raddr    = q_raddr;
      d_col_cnt  = q_col_cnt;
      d_write_en = 1'b0;

      case (q_state)
         ST_IDLE: begin : idle_datapath
            d_raddr   = '0;
            d_col_cnt = '0;
         end
         ST_LOAD, ST_COMPUTE: begin : streaming_datapath
            d_raddr    = q_raddr + 1'b1;
            d_write_en = 1'b1;
         end
      endcase

      if (w_streaming)
         d_col_cnt = (q_col_cnt == col_t'(INPUT_SIZE-1)) ? '0 : q_col_cnt + 1'b1;
   end : datapath_next_logic

   assign o_raddr    = q_raddr;
   assign o_write_en = q_write_en;

endmodule