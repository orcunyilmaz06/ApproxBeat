"""Toolchain self-test: cocotb drives Icarus Verilog and reads a counter back."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly


@cocotb.test()
async def counter_counts(dut):
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 3)
    await ReadOnly()
    first = int(dut.q.value)
    await ClockCycles(dut.clk, 5)
    await ReadOnly()
    assert int(dut.q.value) == first + 5
