class clk_normal_seq extends base_seq #(clk_item);

   `uvm_object_utils(clk_normal_seq)
   real m_freq_mhz = 100;

   // PUBLIC API ────────────────────────────────────────────────────────────────

   extern function new(input string name = "clk_normal_seq");

   extern virtual task body();
   extern function void set_freq_mhz(input real freq_mhz);
endclass


// CONSTRUCTOR ────────────────────────────────────────────────────────────────

function clk_normal_seq::new(input string name = "clk_normal_seq");
   super.new(name);
endfunction


// BODY ───────────────────────────────────────────────────────────────────────

task clk_normal_seq::body();

   clk_item tr = clk_item::type_id::create("tr");

   // Default baseline clock: 100 MHz, no drift, no SSC.
   tr.set_base(m_freq_mhz);
   send_directed_items(tr);

endtask

function void clk_normal_seq::set_freq_mhz(input real freq_mhz);
   this.m_freq_mhz = freq_mhz;
endfunction
