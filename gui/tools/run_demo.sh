#!/usr/bin/env bash
# Spins up a virtual serial pair, streams a synthetic sine wave into one end,
# and launches the GUI pointed at the other end. Ctrl-C or closing the GUI
# tears everything down.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_DIR="$(dirname "$SCRIPT_DIR")"
PORT_A=/tmp/vscope0
PORT_B=/tmp/vscope1

cleanup() {
    trap - EXIT INT TERM
    [[ -n "${FAKE_PID:-}" ]] && kill "$FAKE_PID" 2>/dev/null || true
    [[ -n "${SOCAT_PID:-}" ]] && kill "$SOCAT_PID" 2>/dev/null || true
    rm -f "$PORT_A" "$PORT_B"
}
trap cleanup EXIT INT TERM

rm -f "$PORT_A" "$PORT_B"
socat -d -d "pty,raw,echo=0,link=$PORT_A" "pty,raw,echo=0,link=$PORT_B" &
SOCAT_PID=$!

for _ in $(seq 1 50); do
    [[ -e "$PORT_A" && -e "$PORT_B" ]] && break
    sleep 0.1
done
if [[ ! -e "$PORT_A" || ! -e "$PORT_B" ]]; then
    echo "socat never created $PORT_A / $PORT_B" >&2
    exit 1
fi

python3 "$SCRIPT_DIR/fake_scope.py" --port "$PORT_A" "$@" &
FAKE_PID=$!

if command -v oscilloscope-gui >/dev/null 2>&1; then
    oscilloscope-gui --port "$PORT_B"
else
    (cd "$GUI_DIR" && python3 -m scope_gui.main --port "$PORT_B")
fi
