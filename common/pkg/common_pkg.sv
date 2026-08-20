package common_pkg;

   localparam INPUT_SIZE  = 32;
   localparam KERNAL_SIZE = 3;

   localparam OUTPUT_SIZE = INPUT_SIZE - KERNAL_SIZE + 1;
   localparam MULT_ARRAY_SIZE = KERNAL_SIZE * KERNAL_SIZE;

   typedef logic[7:0]  byte_t;
   typedef logic[15:0] product_t;
   typedef logic[19:0] accum_t;

endpackage