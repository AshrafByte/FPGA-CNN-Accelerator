class reset_manager extends uvm_component;
   `uvm_component_utils(reset_manager)

   bit sync_rst = false;
   local static reset_manager                  m_inst;
   local IResetListener                        m_listeners[$];
   uvm_analysis_imp #(rst_item, reset_manager) m_ap_imp;
   int unsigned                                epoch           = 0;

   extern function new(input string name, uvm_component parent);
   extern static function reset_manager get(input uvm_component parent = null);
   extern function void build_phase(input uvm_phase phase);
   extern function void register(input IResetListener listener);
   extern function void write(input rst_item t);
   extern local function void notify(input rst_event evt);
   extern function void debug_print();
   extern function void enable_sync_rst();

endclass : reset_manager


// CONSTRUCTOR ─────────────────────────────────────────────────────────────────
function reset_manager::new(input string name, uvm_component parent);
   super.new(name, parent);
   m_inst = this;
endfunction


// SINGLETON ACCESS ─────────────────────────────────────────────────────────────
// NOTE: First call must come from env build_phase with a valid parent.
//       All subsequent calls can omit parent.
function reset_manager reset_manager::get(input uvm_component parent = null);
   if (m_inst == null)                   
      m_inst = new("reset_manager", parent);

   return m_inst;
endfunction


// BUILD PHASE ─────────────────────────────────────────────────────────────────
function void reset_manager::build_phase(input uvm_phase phase);
   super.build_phase(phase);
   m_ap_imp = new("m_ap_imp", this);
endfunction


// REGISTRATION ────────────────────────────────────────────────────────────────
// NOTE: Call only from connect_phase or later — never from new()
function void reset_manager::register(input IResetListener listener);
   reset_priority_e new_pri = listener.get_reset_priority();

   // duplicate guard
   foreach (m_listeners[i]) begin
      if (m_listeners[i] == listener) begin
         `uvm_warning("RESET_MGR", "listener already registered — ignoring")
         return;
      end
   end

   // insert at sorted position
   foreach (m_listeners[i]) begin
      if (new_pri < m_listeners[i].get_reset_priority()) begin
         m_listeners.insert(i, listener);
         `uvm_info("RESET_MGR", $sformatf("registered at [%0d] priority=%s", i, new_pri.name()),
                   UVM_HIGH)
         return;
      end
   end

   m_listeners.push_back(listener);
   `uvm_info("RESET_MGR", $sformatf(
             "registered at [%0d] priority=%s", m_listeners.size() - 1, new_pri.name()), UVM_HIGH)
endfunction


// TLM ENTRY POINT FROM MONITOR ────────────────────────────────────────────────
function void reset_manager::write(input rst_item t);
   rst_event evt = rst_event::type_id::create("evt");

   evt.kind      = t.rst_event;
   evt.timestamp = t.timestamp;

   if(sync_rst) begin

      if(evt.kind == RST_ASSERT || evt.kind == RST_RELEASE)
         return;

      if(evt.kind == RST_SYNC_ASSERT)
         evt.kind = RST_ASSERT;
      else
         evt.kind = RST_RELEASE;
      
   end
   if (evt.kind == RST_ASSERT) epoch++;
   evt.epoch = epoch;

   notify(evt);
endfunction


// CORE DISPATCH ───────────────────────────────────────────────────────────────
function void reset_manager::notify(input rst_event evt);
   `uvm_info(
      "RESET_MGR", $sformatf(
      "broadcasting %s (epoch=%0d) to %0d listeners", evt.kind.name(), evt.epoch, m_listeners.size()
      ), UVM_MEDIUM)

   foreach (m_listeners[i]) m_listeners[i].handle_reset(evt);
endfunction


// DEBUG ───────────────────────────────────────────────────────────────────────
// NOTE: Call at end of connect_phase to verify registration order
function void reset_manager::debug_print();
   `uvm_info("RESET_MGR", "=== registered listeners ===", UVM_NONE)
   foreach (m_listeners[i])
      `uvm_info("RESET_MGR", $sformatf(
                "  [%0d] priority=%-12s type=%s",
                i,
                m_listeners[i].get_reset_priority().name(),
                $typename(
                   m_listeners[i]
                )
                ), UVM_NONE)
endfunction

function void reset_manager::enable_sync_rst();
   sync_rst = true;
endfunction