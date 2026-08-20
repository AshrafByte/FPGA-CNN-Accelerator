//------------------------------------------------------------------------------
// Module: kernel_register
//
// Description:
//   Loadable register bank holding a flattened WINDOW_SIZE x WINDOW_SIZE set
//   of kernel weights, configured once and held static during convolution.
//
// Architecture:
//   - Single flat array of WINDOW_SIZE**2 registers, no shifting or windowing
//     logic — purely a load-and-hold configuration register.
//
// Data Flow:
//   - i_load_data is captured into r_weights when i_load_en is asserted.
//   - o_weights continuously reflects the last-loaded values.
//
// Timing:
//   - Load occurs synchronously on the rising clock edge when i_load_en is high.
//   - o_weights is a direct combinational read of the registered weights
//     (zero additional latency once loaded).
//
// Assumptions:
//   - i_load_en is asserted for exactly one cycle per load (or held only as
//     long as a new load is intended); re-asserting overwrites all weights.
//   - Caller does not change i_load_data while i_load_en is low expecting it
//     to be ignored — it simply won't be sampled.
//
// Parameters:
//   PIXEL_WIDTH : Bit width of each weight value.
//   WINDOW_SIZE : Kernel dimension; total weights loaded = WINDOW_SIZE**2.
//------------------------------------------------------------------------------
module kernel_register #(
   parameter  int  PIXEL_WIDTH  = 8,
   parameter  int  WINDOW_SIZE  = 3,

   localparam type pixel_t = logic [PIXEL_WIDTH-1:0]
)(
   input  logic   clk,
   input  logic   rst_n,

   input  logic   i_load_en,
   input  pixel_t i_load_data[WINDOW_SIZE ** 2],

   output pixel_t o_weights[WINDOW_SIZE ** 2]
);

   pixel_t r_weights[WINDOW_SIZE ** 2];

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         r_weights <= '{default: '0};
      else if (i_load_en)
         r_weights <= i_load_data;
   end

   assign o_weights = r_weights;

endmodule