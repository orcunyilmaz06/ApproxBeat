"""Tiny Tapeout test of tt_um_orcunyilmaz06_approxbeat: the smoke vectors through its pins.

Each ADC code goes in by the four-phase handshake of src/project.v (REQ, ACK); the BEAT,
KIND and paged R-peak age and peak outputs must equal the integer model's beat and peak
tables (docs/golden_vectors.md). The same test runs against the gate-level netlist, so it
reads no internal signal.
"""
from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

VECTORS = Path(__file__).resolve().parents[1] / "tb" / "vectors"
REQ, PAGE = 1 << 3, 1 << 4


def u(handle):
    return int(handle.value)


async def reset(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def sample(dut, code):
    """Hand one ADC code to the chip; return (beat, kind, r_age, peak, peak_class)."""
    await FallingEdge(dut.clk)
    dut.ui_in.value = code & 0xFF
    dut.uio_in.value = (code >> 8) | REQ
    await RisingEdge(dut.ack)
    await FallingEdge(dut.clk)
    beat, kind, lo = u(dut.beat), u(dut.kind), u(dut.uo_out)
    dut.uio_in.value = (code >> 8) | REQ | PAGE
    await Timer(1, "ns")                           # the page multiplexer is combinational
    hi = u(dut.uo_out)
    dut.uio_in.value = code >> 8                   # drop REQ and PAGE
    await FallingEdge(dut.ack)
    return beat, kind, ((hi & 0x7) << 8) | lo, (hi >> 3) & 1, (hi >> 4) & 3


def first_diff(got, exp):
    k = next((i for i, (g, e) in enumerate(zip(got, exp)) if g != e), min(len(got), len(exp)))
    g = got[k] if k < len(got) else "none"
    e = exp[k] if k < len(exp) else "none"
    return f"event {k} is {g}, golden {e} ({len(got)} events, golden {len(exp)})"


async def check_stream(dut, stem):
    adu = np.load(f"{stem}_samples.npy")[:, 0].tolist()
    peaks = np.load(f"{stem}_peaks.npy").tolist()   # index, value, class, thr1_used, n, age, ...
    beats = np.load(f"{stem}_beats.npy").tolist()   # n, r_age, kind, ...
    exp_peaks = [(r[4], 2 if r[2] == 4 else r[2]) for r in peaks]
    exp_beats = [(r[0], r[1], r[2] - 1) for r in beats]
    got_peaks, got_beats = [], []
    await reset(dut)
    for n, code in enumerate(adu):
        beat, kind, r_age, peak, cls = await sample(dut, code)
        if peak:
            got_peaks.append((n, cls))
        if beat:
            got_beats.append((n, r_age, kind))
        else:
            assert (kind, r_age) == (0, 0), f"{stem}: sample {n}: KIND or R-age set without a beat"
    name = Path(stem).name
    assert got_peaks == exp_peaks, f"{name}: peak (n, class): {first_diff(got_peaks, exp_peaks)}"
    assert got_beats == exp_beats, f"{name}: beat (n, r_age, kind): {first_diff(got_beats, exp_beats)}"
    dut._log.info("%s: %d samples, %d peaks, %d beats bit-exact", name, len(adu), len(got_peaks),
                  len(got_beats))


@cocotb.test()
async def smoke_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 200, unit="ns").start())    # 5 MHz, as in info.yaml
    stems = sorted(str(p)[:-len("_samples.npy")] for p in VECTORS.glob("*_samples.npy"))
    assert stems, f"no smoke vectors in {VECTORS}"
    for stem in stems:
        await check_stream(dut, stem)
