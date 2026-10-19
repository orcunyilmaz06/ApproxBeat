# Toolchain self-test: cocotb + Icarus Verilog on a counter (scripts/setup_wsl.sh runs it).
# Build output goes to the Linux file system, not into the OneDrive-synced repo.
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES = $(CURDIR)/counter.v
COCOTB_TOPLEVEL = counter
COCOTB_TEST_MODULES = test_counter
SIM_BUILD ?= $(HOME)/.cache/approxbeat/toolcheck
export COCOTB_RESULTS_FILE ?= $(SIM_BUILD)/results.xml
export PYTHONDONTWRITEBYTECODE = 1

include $(shell cocotb-config --makefiles)/Makefile.sim
