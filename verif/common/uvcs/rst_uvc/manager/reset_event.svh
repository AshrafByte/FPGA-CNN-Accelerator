class rst_event extends uvm_object;
      `uvm_object_utils(rst_event)

      rst_event_kind_e kind;
      realtime         timestamp;
      int unsigned     epoch;

      function new(input string name = "rst_event");
         super.new(name);
      endfunction

   endclass