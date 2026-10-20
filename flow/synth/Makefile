# Generic Yosys synthesis of the chip (src/project.v, the Tiny Tapeout top, around
# src/ab_core.v): flip-flop, cell and transistor counts before
# any PDK (the LibreLane runs come later). Writes results/synth_core.md.
#   make                 synthesize and report
# From Windows: scripts\wsl_make.ps1 flow\synth
RTL  = $(CURDIR)/../../src
SRC  = $(RTL)/ab_filters.v $(RTL)/ab_decide.v $(RTL)/ab_core.v $(RTL)/project.v
TOP  = tt_um_approxbeat
OUT ?= $(HOME)/.cache/approxbeat/synth
YOSYS_CMDS = read_verilog $(SRC); hierarchy -check -top $(TOP); synth -top $(TOP); \
             tee -q -o $(OUT)/stat.json stat -json; \
             tee -q -o $(OUT)/stat_cmos.txt stat -tech cmos; \
             tee -q -o $(OUT)/stat.txt stat; \
             write_json $(OUT)/netlist.json

.PHONY: all
all:
	mkdir -p $(OUT)
	yosys -q -l $(OUT)/yosys.log -p "$(YOSYS_CMDS)"
	python3 report.py $(OUT) $(CURDIR)/../../results/synth_core.md $(CURDIR)/../../results/state_inventory.md
