class clk_drift_seq extends base_seq#(clk_item);

   `uvm_object_utils(clk_drift_seq)
   real m_freq_drift_ppm = 600;
   real m_freq_mhz = 100;
   // PUBLIC API ────────────────────────────────────────────────────────────────

   extern function new(input string name = "clk_drift_seq");

   extern virtual task body();
   extern function void set_freq_drift(input real freq_mhz,input real drift_ppm);
endclass


// CONSTRUCTOR ────────────────────────────────────────────────────────────────

function clk_drift_seq::new(input string name = "clk_drift_seq");
   super.new(name);
endfunction


// BODY ───────────────────────────────────────────────────────────────────────

task clk_drift_seq::body();

   clk_item tr = clk_item::type_id::create("tr");
   tr.set_base(m_freq_mhz);
   tr.set_drift(true, m_freq_drift_ppm);
   send_directed_items(tr);

endtask

function void clk_drift_seq::set_freq_drift(input real freq_mhz,input real drift_ppm);
   this.m_freq_drift_ppm = drift_ppm;
   this.m_freq_mhz = freq_mhz;
endfunction
