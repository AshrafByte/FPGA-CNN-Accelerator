package tb_util_pkg;

  import common_pkg::*;

  typedef byte input_t [INPUT_SIZE] [INPUT_SIZE];
  typedef byte kernel_t [KERNAL_SIZE] [KERNAL_SIZE];
  typedef shortint output_t [OUTPUT_SIZE] [OUTPUT_SIZE];
  typedef logic [7:0] pixel_t;

  // compute conv given input feature map & kernal
  function output_t conv
    (
      input input_t i_input,
      input kernel_t i_kernal
    );

    shortint sum;

    for (int r = 0; r < OUTPUT_SIZE; r++) begin
      for (int c = 0; c < OUTPUT_SIZE; c++) begin

        sum = 0;

        for (int kr = 0; kr < KERNAL_SIZE; kr++)
          for (int kc = 0; kc < KERNAL_SIZE; kc++)
            sum += i_input[r+kr][c+kc] * i_kernal[kr][kc];

        conv[r][c] = sum;

      end
    end

  endfunction : conv

  task automatic apply_reset
    (
      ref logic i_clk,
      input int i_cycles = 5,
      ref logic o_rst_n
    );
    o_rst_n = 1'b0;
    repeat (i_cycles) @(posedge i_clk);
    o_rst_n = 1'b1;
    @(posedge i_clk); // one extra edge so rst_n is stable and observed high before returning
  endtask

  task automatic drive_pixels(
    ref logic i_clk,
    input int i_count,
    ref pixel_t o_pixel
  );

    for (int val = 1; val <= i_count; val++) begin
      @(posedge i_clk);
      #1;
      o_pixel = pixel_t'(val);
    end

  endtask

endpackage : tb_util_pkg