#!/bin/bash
# Run oscilloscope GUI with fake sinusoidal test signal
#
# Usage:
#   ./tools/run-fake-scope.sh [--freq 1.0] [--amplitude 400] [--cols 500] [--fps 20]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_DIR="$(dirname "$SCRIPT_DIR")"

# Default arguments
FREQ=1.0
AMPLITUDE=400
COLS=500
FPS=20

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --freq)
            FREQ="$2"
            shift 2
            ;;
        --amplitude)
            AMPLITUDE="$2"
            shift 2
            ;;
        --cols)
            COLS="$2"
            shift 2
            ;;
        --fps)
            FPS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--freq 1.0] [--amplitude 400] [--cols 500] [--fps 20]"
            exit 1
            ;;
    esac
done

# Virtual serial ports
VPORT0="/tmp/vscope0"
VPORT1="/tmp/vscope1"

# Cleanup function
SOCAT_PID=""
FAKE_PID=""

cleanup() {
    echo "Cleaning up..."
    [[ -n "$FAKE_PID" ]] && kill "$FAKE_PID" 2>/dev/null || true
    [[ -n "$SOCAT_PID" ]] && kill "$SOCAT_PID" 2>/dev/null || true
    rm -f "$VPORT0" "$VPORT1"
}

trap cleanup EXIT INT TERM

command -v socat >/dev/null || { echo "socat not found. Install it: sudo dnf install socat"; exit 1; }

cd "$GUI_DIR"
[[ -f .venv/bin/activate ]] || { echo "No venv in $GUI_DIR/.venv. See README 'Host GUI' setup."; exit 1; }
source .venv/bin/activate

# Create virtual serial port pair
echo "Creating virtual serial ports ($VPORT0 ↔ $VPORT1)..."
rm -f "$VPORT0" "$VPORT1"
socat -d -d pty,raw,echo=0,link="$VPORT0" pty,raw,echo=0,link="$VPORT1" &
SOCAT_PID=$!
sleep 1

# Start fake scope in background
echo "Starting fake scope: freq=$FREQ Hz, amplitude=$AMPLITUDE, cols=$COLS, fps=$FPS fps"
python tools/fake_scope.py --port "$VPORT0" --freq "$FREQ" --amplitude "$AMPLITUDE" --cols "$COLS" --fps "$FPS" &
FAKE_PID=$!

sleep 1

# Start GUI
echo "Starting GUI..."
oscilloscope-gui --port "$VPORT1"
