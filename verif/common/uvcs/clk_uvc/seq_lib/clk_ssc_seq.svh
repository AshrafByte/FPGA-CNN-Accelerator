class clk_ssc_seq extends base_seq#(clk_item);

   `uvm_object_utils(clk_ssc_seq)

   // SSC defaults - typical USB/PCIe down-spread profile
   real m_freq_mhz   = 100;
   real m_ssc_ppm    = 5000;   // 5000 ppm (-0.5%) down-spread
   real m_ssc_mod_hz = 33000;  // 33 kHz modulation rate

   // Optional cycle-to-cycle jitter layered on top of SSC (off by default)
   bit  m_jitter_enable = 0;
   real m_jitter_ppm    = 0;

   // PUBLIC API ────────────────────────────────────────────────────────────────

   extern function new(input string name = "clk_ssc_seq");

   extern virtual task body();
   extern function void set_ssc(input real freq_mhz, input real ssc_ppm = 5000, input real mod_hz = 33000 );
   extern function void set_jitter(input bit en, input real jitter_ppm);

endclass


// CONSTRUCTOR ────────────────────────────────────────────────────────────────

function clk_ssc_seq::new(input string name = "clk_ssc_seq");
   super.new(name);
endfunction


// BODY ───────────────────────────────────────────────────────────────────────

task clk_ssc_seq::body();

   clk_item tr = clk_item::type_id::create("tr");
   tr.set_base(m_freq_mhz);
   tr.set_ssc(1'b1, m_ssc_ppm, m_ssc_mod_hz);

   if (m_jitter_enable)
      tr.set_drift(1'b1, m_jitter_ppm);

   send_directed_items(tr);

endtask

// Configure base frequency + SSC profile in one call
function void clk_ssc_seq::set_ssc(input real freq_mhz, input real ssc_ppm = 5000, input real mod_hz = 33000);
   this.m_freq_mhz   = freq_mhz;
   this.m_ssc_ppm    = ssc_ppm;
   this.m_ssc_mod_hz = mod_hz;
endfunction

// Optionally layer cycle-to-cycle jitter on top of the SSC profile
function void clk_ssc_seq::set_jitter(input bit en, input real jitter_ppm);
   this.m_jitter_enable = en;
   this.m_jitter_ppm    = jitter_ppm;
endfunction