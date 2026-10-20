"""End-to-end bit-exact check of src/ab_core.v: ADC codes in, decision events out.

The DUT gets each sample's ADC code (column adu of <stream>_samples.npy); every peak and
beat event must equal the golden tables (ab_tb.EventChecker, docs/golden_vectors.md).

  smoke_vectors  the committed set in tb/vectors (always runs)
  full_records   all 48 records in data/golden, if AB_FULL=1 (AB_RECORDS=100,228 for a
                 subset); a complete run writes results/rtl_core.md
"""
import os
from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

from ab_tb import EventChecker, stems, write_report


async def reset(dut):
    dut.in_valid.value = 0
    dut.in_adu.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1


async def check_stream(dut, stem):
    adu = np.load(f"{stem}_samples.npy")[:, 0].tolist()
    chk = EventChecker(dut, dut.u_decide, Path(stem).name,
                       np.load(f"{stem}_peaks.npy"), np.load(f"{stem}_beats.npy"))
    await reset(dut)
    chk.start()
    for n, code in enumerate(adu):
        await FallingEdge(dut.clk)
        chk.n = n
        dut.in_adu.value = code
        dut.in_valid.value = 1
        await FallingEdge(dut.clk)
        dut.in_valid.value = 0
        await RisingEdge(dut.done)
        if chk.error:
            break
    await FallingEdge(dut.clk)
    chk.stop()
    chk.finish()
    dut._log.info("%s: %d samples, %d peaks, %d beats bit-exact", chk.name, len(adu), chk.ip, chk.ib)
    return len(adu), chk.ip, chk.ib


@cocotb.test()
async def smoke_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    for stem in stems(full=False)[0]:
        await check_stream(dut, stem)


@cocotb.test(skip=os.environ.get("AB_FULL") != "1")
async def full_records(dut):
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    found, subset = stems(full=True)
    counts = {Path(s).name: await check_stream(dut, s) for s in found}
    if not subset:
        write_report("rtl_core.md", "complete RTL detector against the golden vectors",
                     "`src/ab_core.v` (filter chain + decision logic) fed with the ADC code of "
                     "every sample. Every peak event (class, value, age, SPKI, NPKI, THR1) and every "
                     "beat event (R-peak age, kind, SPKI, NPKI, THR1, RR limit) equals the integer "
                     "model's log, end to end.",
                     counts)
