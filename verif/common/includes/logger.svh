class logger;

   // CONDITION IDENTIFIERS ─────────────────────────────────────────────────────
   typedef enum int {
   NONE,

   // Lifecycle
   BUILD,
   CONNECT,
   RESET,
   EOE,

   // Resource/configuration
   CREATE,
   CFG,

   // Transactions
   TR,

   // Errors
   CFG_NOT_FOUND,
   VIF_NOT_FOUND,
   CFG_TYPE_ERR,
   CFG_VIF_NULL,

   PKT_MATCH,
   PKT_MISMATCH,
   TIMEOUT,

   RAND_FAIL,
   CAST_FAIL,
   TEST_FAIL,
   TEST_PASS,
   SQR_NULL,
   AGENT_MODE,

   CFG_FALLBACK
} cond_id_t;

   string prefix = "";

   // PUBLIC API ─────────────────────────────────────────────────────────────────

   extern function new(input string prefix = "");

   extern function string get_id(input string filepath);

   extern function string get_id_cond(input string filepath, input cond_id_t cond_id);

   extern function string get_id_str(input string filepath, input string condition);

   // FILE PARSING UTILITIES (STATIC) ───────────────────────────────────────────

   extern protected static function string extract_comp_id(input string filepath);

   extern protected static function string get_stem(input string filepath);

   extern protected static function string get_suffix(input string stem);

   extern protected static function string comp_suffix_to_id(input string suffix);

   // STRING UTILITIES (STATIC) ─────────────────────────────────────────────────

   extern protected static function int find_last_char(input string s, input string c);

   extern protected static function string str_toupper(input string s);

   extern protected static function string str_tolower(input string s);

   // FORMAT HELPERS ─────────────────────────────────────────────────────────────

   extern protected static function string format_id_full(input string pfx, input string comp_id,
                                                          input string condition);

endclass


// METHOD DEFINITIONS ────────────────────────────────────────────────────────────


// CONSTRUCTOR ──────────────────────────────────────────────────────────────────

function logger::new(input string prefix = "");
   this.prefix = prefix;
endfunction


// PRIMARY API ───────────────────────────────────────────────────────────────────

function string logger::get_id(input string filepath);
   return get_id_cond(filepath, NONE);
endfunction


function string logger::get_id_cond(input string filepath, input cond_id_t cond_id);

   string comp_id = extract_comp_id(filepath);

   if (cond_id == NONE) return format_id_full(this.prefix, comp_id, "");

   return format_id_full(this.prefix, comp_id, cond_id.name());

endfunction


function string logger::get_id_str(input string filepath, input string condition);

   string comp_id = extract_comp_id(filepath);
   return format_id_full(this.prefix, comp_id, str_toupper(condition));

endfunction


// FILE PARSING UTILITIES (STATIC) ───────────────────────────────────────────

function string logger::extract_comp_id(input string filepath);
   return comp_suffix_to_id(get_suffix(get_stem(filepath)));
endfunction


function string logger::get_stem(input string filepath);

   int    slash_idx;
   int    bslash_idx;
   int    last_slash_idx;
   int    dot_idx;
   string filename;

   slash_idx = find_last_char(filepath, "/");
   bslash_idx = find_last_char(filepath, "\\");
   last_slash_idx = (slash_idx > bslash_idx) ? slash_idx : bslash_idx;

   filename = (last_slash_idx < 0) ? filepath :
      filepath.substr(last_slash_idx + 1, filepath.len() - 1);

   dot_idx = find_last_char(filename, ".");

   return (dot_idx > 0) ? filename.substr(0, dot_idx - 1) : filename;

endfunction


function string logger::get_suffix(input string stem);
   int idx = find_last_char(stem, "_");
   return (idx < 0) ? stem : stem.substr(idx + 1, stem.len() - 1);
endfunction


function string logger::comp_suffix_to_id(input string suffix);

   case (str_tolower(
      suffix
   ))

      "monitor", "mon": return "MON";

      "driver", "drv": return "DRV";

      "scoreboard", "sb": return "SB";

      "sequencer", "sqr", "seqr": return "SQR";

      "sequence", "seq": return "SEQ";

      "agent", "agt": return "AGT";

      "coverage", "cov", "cg": return "COV";

      "environment", "env": return "ENV";

      "predictor", "pred", "sb_predictor", "sb_pred": return "PRED";

      "comparator", "cmp", "sb_comparator", "sb_cmp": return "CMP";

      "test", "tst": return "TEST";

      "config", "cfg": return "CFG";

      default: return str_toupper(suffix);

   endcase

endfunction


// STRING UTILITIES (STATIC) ─────────────────────────────────────────────────

function int logger::find_last_char(input string s, input string c);

   for (int i = s.len() - 1; i >= 0; i--) if (s.substr(i, i) == c) return i;

   return -1;

endfunction


function string logger::str_toupper(input string s);

   string result = s;

   for (int i = 0; i < s.len(); i++) begin
      byte c = s[i];
      if (c >= 8'h61 && c <= 8'h7A) result[i] = c - 8'h20;
   end

   return result;

endfunction


function string logger::str_tolower(input string s);

   string result = s;

   for (int i = 0; i < s.len(); i++) begin
      byte c = s[i];
      if (c >= 8'h41 && c <= 8'h5A) result[i] = c + 8'h20;
   end

   return result;

endfunction


// FORMAT HELPERS ─────────────────────────────────────────────────────────────

function string logger::format_id_full(input string pfx, input string comp_id,
                                       input string condition);

   if (pfx.len() == 0 && condition.len() == 0) return comp_id;

   if (pfx.len() == 0) return $sformatf("%s/%s", comp_id, condition);

   if (condition.len() == 0) return $sformatf("%s/%s", pfx, comp_id);

   return $sformatf("%s_%s/%s", pfx, comp_id, condition);

endfunction
