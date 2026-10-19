#!/usr/bin/env bash
# Set up the Linux side of ApproxBeat in WSL2 (Ubuntu 24.04): a Python virtual
# environment with cocotb and numpy for the RTL testbenches. Safe to re-run.
#
# Needs these apt packages first (they ask for your password):
#   sudo apt update && sudo apt install -y git python3-venv iverilog make
# Run from Windows:
#   wsl -d Ubuntu-24.04 --cd <repo> -- bash scripts/setup_wsl.sh
set -euo pipefail

# project venv: $AB_VENV, else the shared /opt/approxbeat/venv if present, else ~/venvs
if [ -n "${AB_VENV:-}" ]; then VENV="$AB_VENV"
elif [ -d /opt/approxbeat/venv ]; then VENV=/opt/approxbeat/venv
else VENV="$HOME/venvs/approxbeat"; fi
REQ="$(dirname "$0")/../tb/requirements.txt"

for t in python3 iverilog vvp make git; do
    command -v "$t" >/dev/null || {
        echo "missing: $t  (sudo apt install -y git python3-venv iverilog make)"; exit 1; }
done

[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
if [ -f "$REQ" ]; then
    "$VENV/bin/pip" install --quiet -r "$REQ"          # pinned versions
else
    "$VENV/bin/pip" install --quiet cocotb numpy       # first run: latest
fi

echo "venv:     $VENV"
echo "python:   $("$VENV/bin/python" --version)"
echo "cocotb:   $("$VENV/bin/cocotb-config" --version)"
echo "numpy:    $("$VENV/bin/python" -c 'import numpy; print(numpy.__version__)')"
echo "iverilog: $(iverilog -V 2>&1 | head -n 1)"

# end-to-end self-test: cocotb drives Icarus on a counter (tb/toolcheck)
LOG="$HOME/.cache/approxbeat/toolcheck.log"
mkdir -p "$(dirname "$LOG")"
if PATH="$VENV/bin:$PATH" make -s -C "$(dirname "$0")/../tb/toolcheck" > "$LOG" 2>&1; then
    echo "toolcheck: PASS"
else
    tail -n 30 "$LOG"; echo "toolcheck: FAIL (log: $LOG)"; exit 1
fi
