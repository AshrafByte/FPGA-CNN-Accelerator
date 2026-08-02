class rst_item extends uvm_sequence_item;

   `uvm_object_utils(rst_item)

   // EVENT CLASSIFICATION ───────────────────────────────────────────────────────

   rst_event_kind_e rst_event;   // ASSERT / RELEASE / SYNC_ASSERT / SYNC_RELEASE

   // MONITOR FIELDS ─────────────────────────────────────────────────────────────

   realtime         timestamp;

   // DRIVER / STIMULUS FIELDS ───────────────────────────────────────────────────

   int              pulse_count;
   realtime         start_delay;
   realtime         assert_time;
   realtime         gap_time;

   // PUBLIC API ─────────────────────────────────────────────────────────────────

   extern function new(input string name = "rst_item");
   extern virtual function string convert2string();
   extern virtual function void do_copy(input uvm_object rhs);

   // CONFIGURATION HELPER API ───────────────────────────────────────────────────
   // Configure as a single reset pulse (most common case).
   extern virtual function void set_pulse(input realtime assert_time,
                                           input realtime start_delay = 0ns);

   // Configure as multiple back-to-back reset pulses.
   extern virtual function void set_pulse_train(input int      pulse_count,
                                                 input realtime assert_time,
                                                 input realtime gap_time,
                                                 input realtime start_delay = 0ns);

endclass


// METHOD DEFINITIONS ────────────────────────────────────────────────────────────

function rst_item::new(input string name = "rst_item");
   super.new(name);
endfunction

function string rst_item::convert2string();

   string msg;

   msg = $sformatf("rst_event=%s", rst_event.name());

   if (timestamp != 0)
      msg = {msg, $sformatf(" timestamp=%0t", timestamp)};

   if ((rst_event == RST_ASSERT || rst_event == RST_SYNC_ASSERT) && pulse_count != 0) begin
      msg = {
         msg,
         $sformatf(
            " pulse_count=%0d start_delay=%0t assert_time=%0t gap_time=%0t",
            pulse_count, start_delay, assert_time, gap_time
         )
      };
   end

   return msg;

endfunction

function void rst_item::do_copy(input uvm_object rhs);

   rst_item rhs_;

   if (!$cast(rhs_, rhs)) begin
      `uvm_fatal("DO_COPY", "Type mismatch in rst_item::do_copy")
   end

   super.do_copy(rhs);

   rst_event   = rhs_.rst_event;
   timestamp   = rhs_.timestamp;

   pulse_count = rhs_.pulse_count;
   start_delay = rhs_.start_delay;
   assert_time = rhs_.assert_time;
   gap_time    = rhs_.gap_time;

endfunction

// CONFIGURATION HELPER API ───────────────────────────────────────────────────

// Single reset pulse: assert for `assert_time`, after optional `start_delay`,
// then release and stay released.
function void rst_item::set_pulse(input realtime assert_time,
                                   input realtime start_delay = 0ns);
   this.rst_event   = RST_ASSERT;
   this.pulse_count = 1;
   this.start_delay = start_delay;
   this.assert_time = assert_time;
   this.gap_time    = 0ns;
endfunction

// Multiple reset pulses with a gap between each (e.g. glitch/POR sequences).
function void rst_item::set_pulse_train(input int      pulse_count,
                                         input realtime assert_time,
                                         input realtime gap_time,
                                         input realtime start_delay = 0ns);
   this.rst_event   = RST_ASSERT;
   this.pulse_count = pulse_count;
   this.start_delay = start_delay;
   this.assert_time = assert_time;
   this.gap_time    = gap_time;
endfunction