# Bit-exact testbench of rtl/ab_filters.v against the golden vectors.
#   make                 smoke set (tb/vectors)
#   make AB_FULL=1       also all 48 records in data/golden (AB_RECORDS=100,228 for a subset)
#   make full-parallel   all 48 records over AB_JOBS=6 simulators (tb/common/full_parallel.mk)
# From Windows: scripts\wsl_make.ps1 tb\filters [AB_FULL=1 | full-parallel]
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES = $(CURDIR)/../../rtl/ab_filters.v
COCOTB_TOPLEVEL = ab_filters
COCOTB_TEST_MODULES = test_filters
SIM_BUILD ?= $(HOME)/.cache/approxbeat/filters
export COCOTB_RESULTS_FILE ?= $(SIM_BUILD)/results.xml
export PYTHONDONTWRITEBYTECODE = 1
export PYTHONPATH := $(CURDIR)/../common:$(PYTHONPATH)
export AB_FULL AB_RECORDS

include $(shell cocotb-config --makefiles)/Makefile.sim

include $(CURDIR)/../common/full_parallel.mk
