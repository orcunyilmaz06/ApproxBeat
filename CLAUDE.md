# CLAUDE.md: ApproxBeat

ApproxBeat is an always-on ECG beat (QRS) detector ASIC built around one question:
**how much arithmetic error can a Pan-Tompkins QRS detector tolerate before beat detection
on MIT-BIH degrades?** The deliverables are an accuracy-area-power Pareto front from real
LibreLane runs and a Tiny Tapeout chip. The owner is applying to VLSI / chip-design MSc
programs (TUM, TU Dresden, RWTH, KIT). The repo is a portfolio piece, so keep it clean and
keep every claim checkable.

## Chain of trust

    float model -> bit-accurate integer model -> RTL -> gate level / GDS

| Stage | Lives in | Checked against | Pass criterion |
|---|---|---|---|
| Float model | `matlab/model/ab_pt_float.m` | MIT-BIH reference annotations | Se, +P per `docs/eval_protocol.md` |
| Integer model | `matlab/model/ab_pt_int.m` | float model | accuracy delta measured and reported (`results/int_study.md`) |
| RTL | `rtl/` (planned) | integer-model golden vectors | bit-exact at every stage, all 48 records |
| GDS | `flow/` (planned) | RTL, gate-level simulation | DRC/LVS clean, timing met |

A stage counts as correct only after its check against the stage before it passes.
Float and integer models share one code path (`ab_pt_detect`, `p.arith`). Keep it that way,
so that a float/int difference can only come from rounding.

Until D14, record 228 sat at a tipping point of the searchback: tiny systematic changes
moved its FN count by ~200 (D12). The outlier-clipped SPKI update removed it
(`results/searchback_study.md`). When comparing variants, still list the per-record
changes. Algorithm choices are made on DS1 and reported on DS2 (`eval_protocol.md`, item 9).

## Rules

1. **Numbers come from scripts.** Accuracy, area, power and timing figures in the README,
   docs or report must come from a results file that a script in this repo generated, and
   should cite that file. When a number changes, regenerate it. Never edit it by hand.
2. After changing `matlab/model/` or `matlab/eval/`, run the unit tests and the full
   evaluation, then report how gross Se / +P moved (before -> after).
3. After changing RTL, run the cocotb regression against the golden vectors. Zero
   mismatches is the only passing result.
4. **The model is a hardware specification.** Keep it causal and sample-by-sample, with
   fixed-size state, constant gains written as shifts or short shift-add sums, no
   data-dependent division, and no lookahead beyond explicit delay lines. Add any new
   register to `ab_state_inventory`; accumulators keep their analytic widths
   (`ab_int_widths`), and approximations go only at memoryless points.
5. **The evaluation protocol (`docs/eval_protocol.md`) is frozen.** Never tune parameters
   on individual records, and never change the protocol to improve a number. Each
   algorithm or protocol change gets an entry in `docs/decisions.md` with its reason and
   its measured effect.
6. Use base MATLAB only, no toolboxes, so anyone with plain MATLAB can reproduce the results.
7. `data/` is never committed. `scripts/get_mitdb.ps1` downloads the data and checks
   SHA-256 sums, and `ab_load_record` verifies the WFDB checksums on every load.

## Commands (from the repo root)

- Unit tests: `matlab -batch "cd('matlab'); ab_test"`. `test_regression` fails when
  `results/*_baseline.csv` no longer match the code, which means the results need regenerating.
- Float evaluation (48 records, ~12 s plus MATLAB startup; writes `results/float_baseline.{csv,md}`):
  `matlab -batch "cd('matlab'); ab_setup; ab_run_eval"`
- Integer model study (~10 min; regenerates both baselines, `range_study`, `state_inventory`,
  `wordlength_grid` and `int_study`): `matlab -batch "cd('matlab'); ab_setup; ab_int_study"`
- Searchback study (~6 min; candidates for the SPKI clip, DS1 choice, robustness):
  `matlab -batch "cd('matlab'); ab_setup; ab_searchback_study"`
- README figures: `matlab -batch "cd('matlab'); ab_setup; ab_make_figures"`
- Download data (~98 MB; PhysioNet is slow, ~20-40 min):
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\get_mitdb.ps1`

## Environment

- Windows 11 with MATLAB R2026b (no Signal Processing Toolbox installed, and none needed)
  and Git for Windows. The repo lives in a OneDrive-synced Desktop folder. Work on
  `feat/...` branches and merge into `main`.
- Planned for the RTL stages: WSL2 (Ubuntu) with Python 3, cocotb and Icarus Verilog or
  Verilator, plus LibreLane via Nix. None of these are installed yet. Clone the repo inside
  the WSL file system rather than working on `/mnt/c` (much faster). See `docs/ROADMAP.md`.

## Conventions

- MATLAB: one function per file with an `ab_` prefix. Every output uses 0-based sample
  indices (the WFDB and RTL convention). Times are in seconds.
- Verilog (planned): Verilog-2005 that Yosys accepts. One clock `clk`, synchronous
  active-low reset `rst_n` (the Tiny Tapeout convention), explicit `$signed`, and a cocotb
  test for every module.
- Code, comments, docs and commit messages are in English. The owner may chat in Turkish.
