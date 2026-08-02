class rst_normal_seq extends base_seq #(rst_item);

   `uvm_object_utils(rst_normal_seq)

   // CONFIGURATION FIELDS ───────────────────────────────────────────────────────

   int      m_pulse_count = 1;
   realtime m_start_delay = 2ns;
   realtime m_assert_time = 5ns;
   realtime m_gap_time    = 0ns;

   // PUBLIC API ────────────────────────────────────────────────────────────────

   extern function new(input string name = "rst_normal_seq");

   extern virtual task body();

   // SETTERS ────────────────────────────────────────────────────────────────────
   extern function void set_pulse(input realtime assert_time, input realtime start_delay = 0ns);
   extern function void set_pulse_train(input int      pulse_count,
                                         input realtime assert_time,
                                         input realtime gap_time,
                                         input realtime start_delay = 0ns);

endclass


// CONSTRUCTOR ────────────────────────────────────────────────────────────────

function rst_normal_seq::new(input string name = "rst_normal_seq");
   super.new(name);
endfunction


// BODY ───────────────────────────────────────────────────────────────────────

task rst_normal_seq::body();

   rst_item tr = rst_item::type_id::create("tr");

   // Default: single 15ns pulse, no delay (unless overridden via setters)
   tr.rst_event   = RST_ASSERT;
   tr.pulse_count = m_pulse_count;
   tr.start_delay = m_start_delay;
   tr.assert_time = m_assert_time;
   tr.gap_time    = m_gap_time;

   send_directed_items(tr);

endtask


// SETTERS ────────────────────────────────────────────────────────────────────

function void rst_normal_seq::set_pulse(input realtime assert_time, input realtime start_delay = 0ns);
   this.m_pulse_count = 1;
   this.m_assert_time = assert_time;
   this.m_start_delay = start_delay;
   this.m_gap_time    = 0ns;
endfunction

function void rst_normal_seq::set_pulse_train(input int      pulse_count,
                                               input realtime assert_time,
                                               input realtime gap_time,
                                               input realtime start_delay = 0ns);
   this.m_pulse_count = pulse_count;
   this.m_assert_time = assert_time;
   this.m_gap_time    = gap_time;
   this.m_start_delay = start_delay;
endfunction