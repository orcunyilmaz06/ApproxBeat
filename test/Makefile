# Tiny Tapeout testbench of tt_um_approxbeat (layout of ttgf-verilog-template).
#   make              RTL: the committed smoke vectors through the chip's pins (test.py)
#   make GATES=yes    the same against gate_level_netlist.v (run by the TT GL-test action)
# From Windows: scripts\wsl_make.ps1 test
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(CURDIR)/../src
PROJECT_SOURCES = project.v ab_core.v ab_filters.v ab_decide.v

ifneq ($(GATES),yes)

# RTL simulation
SIM_BUILD = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate-level simulation of the hardened netlist
SIM_BUILD = sim_build/gl
COMPILE_ARGS += -DGL_TEST
COMPILE_ARGS += -DFUNCTIONAL
COMPILE_ARGS += -DUSE_POWER_PINS
COMPILE_ARGS += -DSIM
COMPILE_ARGS += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/gf180mcu_fd_sc_mcu7t5v0.v
VERILOG_SOURCES += $(CURDIR)/gate_level_netlist.v

endif

COMPILE_ARGS += -I$(SRC_DIR)
VERILOG_SOURCES += $(CURDIR)/tb.v
COCOTB_TOPLEVEL = tb
COCOTB_TEST_MODULES = test
FST ?= -fst

include $(shell cocotb-config --makefiles)/Makefile.sim
