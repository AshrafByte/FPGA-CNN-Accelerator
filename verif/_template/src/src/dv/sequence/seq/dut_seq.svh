class dut_seq extends base_seq #(dut_uvc_item);

   `uvm_object_utils(dut_seq)

   // CONSTRUCTOR ───────────────────────────────────────────────────────────────

   extern function new(input string name = "dut_seq");

   // CUSTOMIZATION HOOKS ───────────────────────────────────────────────────────

   // extern virtual function void apply_constraints(
   //    input dut_uvc_item tr
   // );

   // extern virtual function void randomize_item(
   //    input dut_uvc_item tr
   // );

   // SEQUENCE API ──────────────────────────────────────────────────────────────

   extern virtual task body();

endclass


// METHOD DEFINITIONS ───────────────────────────────────────────────────────────


// ─── CONSTRUCTOR ──────────────────────────────────────────────────────────────

function dut_seq::new(input string name = "dut_seq");
   super.new(name);
endfunction


// ─── CUSTOMIZATION HOOKS ──────────────────────────────────────────────────────

// function void dut_seq::apply_constraints(input dut_uvc_item tr);

//    `log_full("Applying sequence constraints")

//    /*
//       Called by send_rand_items() before randomization.

//       Examples:

//       // Disable all constraints
//       tr.constraint_mode(0);

//       // Disable a specific constraint
//       tr.some_constraint.constraint_mode(0);
//    */

// endfunction


// function void dut_seq::randomize_item(input dut_uvc_item tr);

//    /*
//       Called by send_rand_items() to customize randomization.

//       Examples:

//       1) Explicit randomization

//          if (!(tr.randomize() with {
//             din == 10;
//          })) begin
//             `log_rand_err("Randomization failed")
//          end

//       2) Framework helper

//          `rand_with(tr,{
//             din == 10;
//          })
//    */

// endfunction


// TODO BODY ─────────────────────────────────────────────────────────────────────

task dut_seq::body();

   // CREATE TRANSACTION ───────────────────────────────────────────────────────
   dut_uvc_item tr = dut_uvc_item::type_id::create("tr");

   // DIRECTED STIMULUS ────────────────────────────────────────────────────────
   send_directed_items(tr.set(
      // GEN:BEGIN INPUT LIST
      .i_din(0)
      // GEN:END
   ), 5);
   
   // RANDOM STIMULUS ────────────────────────────────────────────────────────
   send_rand_items(100);

   /*
      Alternative random stimulus:

      // Send 100 randomized transactions using the provided transaction
      send_rand_items(100, tr);

      // Send 100 randomized transactions using internally created transactions
      send_rand_items(100);
   */

   /*
      Custom transaction examples:

      1) Explicit randomization

         start_item(tr);

         if (!(tr.randomize() with {
            din == 12;
         })) begin
            `log_rand_err("Randomization failed")
         end

         finish_item(tr);

      2) Using framework helper

         start_item(tr);

         `rand_with(tr,{
            din == 15;
         })

         finish_item(tr);

      3) Single-step helper

         `send_rand_with(tr,{
            din == 15;
         })

      Why not use `uvm_do_with?

      `uvm_do_with was deprecated in IEEE UVM 1800.2-2017.
      Prefer explicit start_item()/finish_item() or framework helper macros.
   */

endtask
