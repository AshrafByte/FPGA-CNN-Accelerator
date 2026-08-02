class custom_report_server extends uvm_default_report_server;

   `uvm_object_utils(custom_report_server)

   // REPORT STATISTICS ────────────────────────────────────────────────────────

   protected int unsigned m_id_count[string];

   // CONSTRUCTION ─────────────────────────────────────────────────────────────

   extern function new(input string name = "custom_report_server");

   // REPORT FORMATTING ────────────────────────────────────────────────────────

   extern virtual function string compose_report_message(input uvm_report_message report_message,
                                                         input string report_object_name = "");

   extern virtual function void report_summarize(input UVM_FILE file = 0);

   extern virtual function void set_timeformat(input string unit = "ns");

endclass


// CONSTRUCTION ────────────────────────────────────────────────────────────────

function custom_report_server::new(input string name = "custom_report_server");

   super.new(name);

endfunction


// REPORT FORMATTING ───────────────────────────────────────────────────────────

function string custom_report_server::compose_report_message(
   input uvm_report_message report_message, input string report_object_name = "");

   string msg_string;
   string file_loc;

   string long_filename;
   string short_filename;

   string report_id;
   string severity_str;
   string time_str;

   // TRACK REPORT IDS ────────────────────────────────────────────────────────

   report_id = report_message.get_id();

   if (report_id == "") report_id = "<NO_ID>";

   if (m_id_count.exists(report_id)) m_id_count[report_id]++;
   else m_id_count[report_id] = 1;

   // STRIP PATH FROM FILE NAME ───────────────────────────────────────────────

   long_filename  = report_message.get_filename();
   short_filename = long_filename;

   for (int i = long_filename.len() - 1; i >= 0; i--) begin

      if ((long_filename[i] == "/") || (long_filename[i] == "\\")) begin

         short_filename = long_filename.substr(i + 1, long_filename.len() - 1);

         break;

      end

   end

   // SEVERITY STRING ─────────────────────────────────────────────────────────

   case (report_message.get_severity())

      UVM_INFO: severity_str = "INFO";

      UVM_WARNING: severity_str = "WARN";

      UVM_ERROR: severity_str = "ERROR";

      UVM_FATAL: severity_str = "FATAL";

      default: severity_str = "UNKWN";

   endcase

   // TIME STRING ─────────────────────────────────────────────────────────────

   time_str = $sformatf("%0t", $time);

   // FORMAT REPORT MESSAGE ───────────────────────────────────────────────────



   file_loc = $sformatf("%s(%0d)", short_filename, report_message.get_line());

   msg_string = $sformatf(
      "%-5s %-40s          @ %0t %-10s [%-24s] %s\n",
      severity_str,
      file_loc,
      $realtime,
      report_object_name,
      string'(report_id),
      report_message.get_message()
   );

   return msg_string;

endfunction


// REPORT SUMMARY ──────────────────────────────────────────────────────────────

function void custom_report_server::report_summarize(input UVM_FILE file = 0);

   string summary;

   summary = "\n\n";

   // SEVERITY SUMMARY ────────────────────────────────────────────────────────

   summary = {
      summary,
      "┌──────────────────────────────────────────────────────────────┐\n"
         ,
      "│ UVM REPORT SUMMARY                                           │\n",
      "├──────────────┬───────────────────────────────────────────────┤\n"
         ,
      "│ Severity     │ Count                                         │\n",
      "├──────────────┼───────────────────────────────────────────────┤\n"
   };

   summary = {summary, $sformatf("│ %-12s │ %45d │\n", "INFO", get_severity_count(UVM_INFO))};

   summary = {
      summary, $sformatf("│ %-12s │ %45d │\n", "WARNING", get_severity_count(UVM_WARNING))
   };

   summary = {
      summary, $sformatf("│ %-12s │ %45d │\n", "ERROR", get_severity_count(UVM_ERROR))
   };

   summary = {
      summary, $sformatf("│ %-12s │ %45d │\n", "FATAL", get_severity_count(UVM_FATAL))
   };

   summary = {
      summary,
      "└──────────────┴───────────────────────────────────────────────┘\n\n"
   };

   // REPORT ID SUMMARY ───────────────────────────────────────────────────────

   summary = {
      summary,
      "┌──────────────────────────────────────────┬───────────────────┐\n"
         ,
      "│ Report ID                                │ Count             │\n",
      "├──────────────────────────────────────────┼───────────────────┤\n"
   };

   foreach (m_id_count[id]) begin

      summary = {summary, $sformatf("│ %-40s │ %17d │\n", id, m_id_count[id])};

   end

   summary = {
      summary,
      "└──────────────────────────────────────────┴───────────────────┘\n"
   };

   if (file == 0) $display("%s", summary);
   else $fwrite(file, "%s", summary);

endfunction


function void custom_report_server::set_timeformat(input string unit = "ns");
   int units_number;

   // Map the string unit to the correct $timeformat integer exponent
   case (unit)
      "s"  : units_number = 0;   // 1s
      "ms" : units_number = -3;  // 1ms = 10^-3s
      "us" : units_number = -6;  // 1us = 10^-6s
      "ns" : units_number = -9;  // 1ns = 10^-9s
      "ps" : units_number = -12; // 1ps = 10^-12s
      "fs" : units_number = -15; // 1fs = 10^-15s
      default: begin
         units_number = -9;      // Fallback default to nanoseconds
         unit = "ns";
      end
   endcase

   // Arguments: (units_number, precision, suffix_string, minimum_field_width)
   $timeformat(units_number, 1, unit, 12);
endfunction

