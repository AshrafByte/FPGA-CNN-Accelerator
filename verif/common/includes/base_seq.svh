class base_seq #(
   type REQ = uvm_sequence_item
) extends uvm_sequence #(REQ);

   `uvm_object_param_utils(base_seq#(REQ))
   int m_total_seq_items = 0;
   // TYPE DECLARATION ─────────────────────────────────────────────────────────
   typedef enum bit {
      DIRECTED,
      RAND
   } seq_mode_e;


   // CONSTRUCTOR ─────────────────────────────────────────────────────────────
   extern function new(input string name = "base_seq");


   // RAND HOOKS ──────────────────────────────────────────────────────────────
   extern virtual function void apply_constraints(input REQ tr);
   extern virtual function void randomize_item(input REQ tr);

   // WRAPPERS ────────────────────────────────────────────────────────────────
   extern protected task send_rand_items(input int unsigned n = 1, input REQ tr = null);
   extern protected task send_directed_items(input REQ tr, input int unsigned n = 1);

   // CORE API ────────────────────────────────────────────────────────────────
   extern local task send_items(input REQ tr, input seq_mode_e mode = DIRECTED,
                                input int unsigned n = 1);

   // GETTERS ───────────────────────────────────────────────────────────────
   extern function int get_total_seq_items();

endclass


// CONSTRUCTOR ───────────────────────────────────────────────────────────────
function base_seq::new(input string name = "base_seq");
   super.new(name);

   `uvm_info(get_type_name().toupper(), $sformatf("base_seq created: %s", name), UVM_LOW)
endfunction


// CORE ENGINE ───────────────────────────────────────────────────────────────
task base_seq::send_items(input REQ tr, input seq_mode_e mode = DIRECTED, input int unsigned n = 1);

   if (n == 0) n = 1;

   `uvm_info(get_type_name().toupper(), $sformatf("send_items started: mode=%s n=%0d",
                                                  (mode == RAND) ? "RAND" : "DIRECTED", n),
             UVM_FULL)

   repeat (n) begin

      REQ item;

      item = REQ::type_id::create("item");
      item.copy(tr);

      start_item(item);

      if (mode == RAND) begin

         `uvm_info(get_type_name().toupper(), "applying constraints + randomization", UVM_FULL)

         apply_constraints(item);
         randomize_item(item);

      end

      finish_item(item);
      m_total_seq_items++; 

   end

   `uvm_info(get_type_name().toupper(), "send_items completed", UVM_FULL)

endtask


// RAND HOOKS ────────────────────────────────────────────────────────────────
function void base_seq::apply_constraints(input REQ tr);

   `uvm_info(get_type_name().toupper(), $sformatf(
             "apply_constraints() default no-op for item: %s", tr.get_full_name().toupper()),
             UVM_FULL)

endfunction


function void base_seq::randomize_item(input REQ tr);

   if (!tr.randomize()) begin
      `uvm_error(get_type_name().toupper(), "randomization failed in base_seq")
   end

endfunction


// WRAPPERS ────────────────────────────────────────────────────────────────
task base_seq::send_rand_items(input int unsigned n = 1, input REQ tr = null);

   `uvm_info(get_type_name().toupper(), "send_rand_items() called", UVM_HIGH)
   if (tr == null) tr = REQ::type_id::create("random item");
   send_items(tr, RAND, n);

endtask


task base_seq::send_directed_items(input REQ tr, input int unsigned n = 1);

   `uvm_info(get_type_name().toupper(), "send_directed_items() called", UVM_HIGH)

   send_items(tr, DIRECTED, n);

endtask


function int base_seq:: get_total_seq_items();
   return m_total_seq_items;
endfunction