# End-to-end bit-exact testbench of rtl/ab_core.v (filters + decision logic).
#   make                 smoke set (tb/vectors)
#   make AB_FULL=1       also all 48 records in data/golden (AB_RECORDS=100,228 for a subset)
# From Windows: scripts\wsl_make.ps1 tb\core [AB_FULL=1]
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
RTL = $(CURDIR)/../../rtl
VERILOG_SOURCES = $(RTL)/ab_filters.v $(RTL)/ab_decide.v $(RTL)/ab_core.v
COCOTB_TOPLEVEL = ab_core
COCOTB_TEST_MODULES = test_core
SIM_BUILD ?= $(HOME)/.cache/approxbeat/core
export COCOTB_RESULTS_FILE ?= $(SIM_BUILD)/results.xml
export PYTHONDONTWRITEBYTECODE = 1
export PYTHONPATH := $(CURDIR)/../common:$(PYTHONPATH)
export AB_FULL AB_RECORDS

include $(shell cocotb-config --makefiles)/Makefile.sim
