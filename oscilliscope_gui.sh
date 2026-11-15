#!/usr/bin/env bash
# Usage: ./oscilliscope_gui.sh [port]   (default: auto-detect the ESP32's CP2102)
set -e
# ttyUSB numbers depend on plug-in order and the FPGA's debugger takes two,
# so find the ESP32 by its USB-UART chip (Silicon Labs CP210x).
PORT="${1:-$(ls /dev/serial/by-id/*CP210* 2>/dev/null | head -n1)}"
cd "$(dirname "$0")/gui"
source .venv/bin/activate
oscilloscope-gui --list
if [ -n "$PORT" ]; then
    oscilloscope-gui --port "$PORT"
else
    echo "ESP32 (CP210x) not found; opening without connecting" >&2
    oscilloscope-gui
fi
