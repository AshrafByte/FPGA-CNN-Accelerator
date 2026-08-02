interface class IResetListener; 
   pure virtual function void handle_reset(input rst_event evt);
   pure virtual function reset_priority_e get_reset_priority();
endclass
