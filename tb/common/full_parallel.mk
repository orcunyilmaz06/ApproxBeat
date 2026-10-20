# make full-parallel [AB_JOBS=6]: the AB_FULL=1 run of all 48 records, split over AB_JOBS
# simulators that each take every AB_JOBS-th record (ab_tb.stems). The shard that finishes
# last writes the results report (ab_tb.write_report). Included after Makefile.sim.
AB_JOBS ?= 6
AB_PARTS ?= $(SIM_BUILD)-parts
export AB_PARTS
AB_SHARDS := $(shell seq 0 $$(($(AB_JOBS) - 1)))

.PHONY: full-parallel
full-parallel:
	rm -rf $(AB_PARTS) $(SIM_BUILD)-shard*
	$(MAKE) --no-print-directory -j$(AB_JOBS) $(addprefix ab-shard-,$(AB_SHARDS))
	@grep -h 'TESTS=' $(SIM_BUILD)-shard*.log
	@! grep -l 'FAIL=[1-9]' $(SIM_BUILD)-shard*.log
	@test $$(ls $(AB_PARTS)/*_of_$(AB_JOBS).json | wc -l) -eq $(AB_JOBS)
	@echo "full-parallel: $(AB_JOBS) shards passed, report written"

ab-shard-%:
	@echo "shard $*/$(AB_JOBS) started"
	@$(MAKE) --no-print-directory AB_FULL=1 AB_SHARD=$*/$(AB_JOBS) SIM_BUILD=$(SIM_BUILD)-shard$* \
	  COCOTB_RESULTS_FILE=$(SIM_BUILD)-shard$*/results.xml > $(SIM_BUILD)-shard$*.log 2>&1 \
	  || (tail -40 $(SIM_BUILD)-shard$*.log; exit 1)
	@echo "shard $*/$(AB_JOBS) done"
