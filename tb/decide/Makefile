# Bit-exact testbench of rtl/ab_decide.v against the golden decision log.
#   make                 smoke set (tb/vectors)
#   make AB_FULL=1       also all 48 records in data/golden (AB_RECORDS=100,228 for a subset)
# From Windows: scripts\wsl_make.ps1 tb\decide [AB_FULL=1]
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES = $(CURDIR)/../../rtl/ab_decide.v
COCOTB_TOPLEVEL = ab_decide
COCOTB_TEST_MODULES = test_decide
SIM_BUILD ?= $(HOME)/.cache/approxbeat/decide
export COCOTB_RESULTS_FILE ?= $(SIM_BUILD)/results.xml
export PYTHONDONTWRITEBYTECODE = 1
export PYTHONPATH := $(CURDIR)/../common:$(PYTHONPATH)
export AB_FULL AB_RECORDS

include $(shell cocotb-config --makefiles)/Makefile.sim
