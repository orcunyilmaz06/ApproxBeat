# Roadmap

Shuttle dates were checked against <https://tinytapeout.com/runs> on 2026-10-19.

## Progress

- **Week 1, done (2026-10-19).** Data pipeline, float model and scoring are in place
  (`results/float_baseline.md`).
- **Week 2, ahead of schedule (2026-10-19).**
  - Done: the bit-accurate integer model, the dynamic-range study, the register inventory and
    a first word-length / accuracy grid (`results/int_study.md`).
  - Robust searchback (D14), done. It was chosen on DS1 and confirmed on the held-out DS2,
    and record 228 is no longer a tipping point (`results/searchback_study.md`).
  - Golden vectors, done: the format and RTL contract (`docs/golden_vectors.md`), the full
    set and the committed smoke set.
  - WSL2 toolchain, done: Ubuntu 24.04, Icarus Verilog 12, cocotb 2.1, with an
    end-to-end self-test (`scripts/setup_wsl.sh`, `scripts/wsl_make.ps1`).
- **Weeks 3-4, done early (2026-10-20).** The complete RTL detector is bit-exact on all 48
  records, end to end from the ADC codes. That covers the filter chain (`rtl/ab_filters.v`)
  and the decision logic (`rtl/ab_decide.v`), joined in `rtl/ab_core.v`, with results in
  `results/rtl_filters.md` and `results/rtl_core.md`.
- **Generic synthesis, done (2026-10-20).** 1,516 flip-flops and 7,057 logic cells; the
  flip-flops reconcile with the inventory to within 1.7 % (`results/synth_core.md`, D16).
  Next:
  - Area closure: share the adders of the decision logic (D15, D16).
  - The Tiny Tapeout wrapper and its I/O protocol.
  - A GitHub repository for the TT GitHub Action.
  - LibreLane for real area.

## Shuttles

| Run | Process | Closes | Chips expected | Est. shipping | Role |
|---|---|---|---|---|---|
| TTSKY26d | SkyWater 130 nm | 2026-11-30 | 2027-05-12 | 2027-06-09 | backup: same delivery, one week earlier |
| **TTGF26c** | GF 180 nm (wafer.space run #3) | **2026-12-07** | 2027-05-12 | 2027-06-09 | **v1 target** |
| TTIHP27a | IHP SG13G2 130 nm | March 2027 (planned) | - | Q1 2028 | v2: best approximate variant |
| TTGF27a | GF 180 nm | April 2027 (planned) | - | October 2027 | late fallback |

Only TTGF26c and TTSKY26d put silicon in hand (June 2027) while admission interviews are
still running (March to early August 2027). Moving v1 to TTIHP27a still earns a "taped out"
CV line, but that chip arrives in Q1 2028.

## Plan

| Week | Dates | Goal | Done when |
|---|---|---|---|
| 1 | Oct 19-25 | Foundations: repo, data pipeline, float model, scoring harness | `ab_test` passes; float Se / +P on all 48 records in `results/float_baseline.md` |
| 2 | Oct 26-Nov 1 | Bit-accurate integer model, word-length study, area budget, Linux toolchain | integer model within 0.05 pp of float; state inventory with bit widths; WSL2 + cocotb + Icarus running |
| 3 | Nov 2-8 | RTL filter chain, golden vectors, cocotb | bit-exact against the integer model on all 48 records |
| 4 | Nov 9-15 | RTL decision logic | full detector bit-exact; RTL Se / +P equal to the integer model's |
| 5 | Nov 16-22 | Tiny Tapeout wrapper (I/O protocol) and first GDS | TT GitHub Action green |
| 6 | Nov 23-29 | Area and timing closure, gate-level simulation | fits the chosen tile count, gate-level sim bit-exact; GF180 (Dec 7) or SKY130 (Nov 30) decided by Nov 27 |
| 7 | Nov 30-Dec 7 | Buffer, documentation, submission | submitted to TTGF26c |
| | January | GRE month, project kept light | |
| | Feb-Mar | Approximate-arithmetic study, Pareto front, 4-6 page IEEE-format report | report draft sent to the CMOS instructor for feedback |
| | March 2027 | Optional: best variant to TTIHP27a | |
| | June 2027 | v1 silicon (est.): measure on the TT demo board | silicon Se / +P on MIT-BIH |

If week 3 or 4 slips by more than a few days, cut scope rather than the deadline: tape out
the exact detector first and leave every approximation to v2.

## Settle these in week 2

1. **Area budget: the delay lines dominate, not the multiplier.** The filter chain stores
   12 (LP) + 32 (HP) + 4 (derivative) + 30 (MWI) = 78 past samples. At 12-24 bits per word
   that is on the order of 1,000-1,800 flip-flops before any decision logic, while the
   squarer is a single multiplier. Measure it with Yosys on the integer model's word
   lengths before writing much RTL. Then check the tile area for the chosen shuttle on the
   Tiny Tapeout site and decide between several tiles and a compressed architecture (for
   example a recursive integrator instead of the 30-word MWI, or narrower stored words).
   This also shapes the research: approximation knobs should cover the **word length of
   stored samples** as well as approximate multipliers and adders, because storage is
   where the area is.
2. **A Linux toolchain on Windows.** LibreLane, cocotb and Icarus/Verilator run best on
   Linux. Install WSL2 (`wsl --install -d Ubuntu-24.04`, which needs administrator rights
   and a reboot), then git, Python 3, cocotb and Icarus Verilog inside Ubuntu. Tiny Tapeout's
   GitHub Action can harden the v1 design without a local flow, so local LibreLane is first
   needed for the Feb-Mar PPA sweep.
3. **Chip I/O.** A tile has 8 inputs, 8 outputs and 8 bidirectional pins. One candidate: an
   11-bit sample on `ui_in[7:0]` + `uio[2:0]` with a strobe on `uio[3]`, and a beat pulse
   plus the R-peak offset on `uo_out`. The demo board's RP2040 can then stream all 48 records
   faster than real time and count beats, which gives **silicon-measured Se / +P**.
