# =============================================================================
# Top-Level Verification Makefile
# =============================================================================
# Provides a standard `make <target> IP=...` interface for the team. 
# Execution logic, module resolution, and simulator dispatching are handled 
# entirely by common/scripts/python/vrun.py.
#
# USAGE:
#   make list
#   make sim        IP=rx_decoder
#   make verify     IP=rx_decoder [TEST=name] [SIMULATOR=dsim]
#   make verify     IP=tx VERBOSITY_MAP="tx_encoder=high,tx_width_converter=low"
#   make compile    IP=hw/rx_decoder or IP=verif/rx_decoder
#   make wave       IP=hw/rx_decoder or IP=verif/rx_decoder   (always GUI, no GUI=1 needed)
#   make clean      IP=hw/rx_decoder or IP=verif/rx_decoder
#   make clean-all
#   make regress-all [PATTERN=verif/*]
#   make uvm_tb     IP=rx_decoder [TARGET=name] [OUTPUT=path] [OVERWRITE=1] [EXCLUDE="pat1 pat2"] [DUMP_PORTS=path]
#     Scaffolds a new UVM environment from generate_uvm_env.py - IP is the
#     DUT name/path (searched under hw/ if bare), TARGET is the replacement
#     name used throughout the generated files (defaults to IP's name).
#     Existing output is left untouched unless OVERWRITE=1 (which deletes it
#     first - no backup). See that script's own --help for full details.
#
# TOP auto-detection expects a testbench named <ip>_uvm_tb.sv under verif/,
# or <ip>_tb.sv under hw/. If yours doesn't follow that, pass TOP= explicitly.
#
# RECORD defaults ON (signals recorded every run) so a failed run never needs
# re-running just to get waveform data - `make wave` afterward just opens
# what was already captured. Pass RECORD=0 to skip recording for runs you
# know you won't need to debug, e.g. a large regress-all sweep.
#
# Note: Variables are forwarded to vrun.py as command flags. 
# Run `make help` to view all available runner options.
# =============================================================================

PYTHON ?= python
VRUN   := common/scripts/python/vrun.py
GEN_SCRIPT := verif/_template/generate_uvm_env.py

# --- Pass-through Variables (Optional) ---
SIMULATOR    ?=
TOP          ?=
TEST         ?=
SEED         ?=
GUI          ?=
COVERAGE     ?=
RECORD       ?= 1
UVM_VER      ?=
PATTERN      ?=
VERBOSITY    ?=
VERBOSITY_MAP ?= # Format: "uvc1=high,uvc2=low"

# --- uvm_tb-specific Pass-through Variables (Optional) ---
TARGET       ?=
OUTPUT       ?=
OVERWRITE    ?=
EXCLUDE      ?=
DUMP_PORTS   ?=

# Dynamically construct command-line flags only for populated variables
# to ensure vrun.py's internal defaults (and auto-detection) are respected.
FLAGS = \
	$(if $(SIMULATOR),--simulator $(SIMULATOR)) \
	$(if $(TOP),--top $(TOP)) \
	$(if $(TEST),--test $(TEST)) \
	$(if $(SEED),--seed $(SEED)) \
	$(if $(VERBOSITY),--verbosity $(VERBOSITY)) \
	$(if $(VERBOSITY_MAP),--verbosity-map "$(VERBOSITY_MAP)") \
	$(if $(filter 1,$(GUI)),--gui) \
	$(if $(filter 1,$(COVERAGE)),--coverage) \
	$(if $(filter 0,$(RECORD)),--no-record) \
	$(if $(UVM_VER),--uvm-ver $(UVM_VER))


GEN_FLAGS = \
	$(if $(OUTPUT),--output $(OUTPUT)) \
	$(if $(filter 1,$(OVERWRITE)),--overwrite) \
	$(if $(EXCLUDE),--exclude $(EXCLUDE)) \
	$(if $(DUMP_PORTS),--dump-ports $(DUMP_PORTS))

.PHONY: help list sim verify compile wave clean clean-all regress-all uvm_tb

help:
	@$(PYTHON) $(VRUN) --help

list:
	@$(PYTHON) $(VRUN) list

sim:
	@$(PYTHON) $(VRUN) sim $(IP) $(FLAGS)

verify:
	@$(PYTHON) $(VRUN) verify $(IP) $(FLAGS)

compile:
	@$(PYTHON) $(VRUN) compile $(IP) $(FLAGS)

wave:
	@$(PYTHON) $(VRUN) wave $(IP) $(FLAGS)

clean:
	@$(PYTHON) $(VRUN) clean $(IP) $(FLAGS)

clean-all:
	@$(PYTHON) $(VRUN) clean-all

regress-all:
	@$(PYTHON) $(VRUN) regress-all $(if $(PATTERN),--pattern "$(PATTERN)") $(FLAGS)

uvm_tb:
	@$(PYTHON) $(GEN_SCRIPT) $(IP) $(TARGET) $(GEN_FLAGS)