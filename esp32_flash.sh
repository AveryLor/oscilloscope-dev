#!/usr/bin/env bash
# Usage: ./esp32_flash.sh [port]   (default: auto-detect the ESP32's CP2102)
set -e
# ttyUSB numbers depend on plug-in order and the FPGA's debugger takes two,
# so find the ESP32 by its USB-UART chip (Silicon Labs CP210x, 10c4:ea60).
PORT="${1:-$(ls /dev/serial/by-id/*CP210* 2>/dev/null | head -n1)}"
if [ -z "$PORT" ]; then
    echo "ESP32 (CP210x) not found; plug it in or pass the port: $0 /dev/ttyUSBx" >&2
    exit 1
fi
echo "Flashing ESP32 on $PORT"
. ~/esp/esp-idf/export.sh
cd "$(dirname "$0")/esp32"

# Only set the target on a fresh checkout; set-target wipes build/.
if [ ! -f build/CMakeCache.txt ]; then
    idf.py set-target esp32
fi

# Incremental build: only changed files recompile.
idf.py build

# --no-stub: the stub loader fails on this board's serial link
# ("Failed to start stub"); the ROM loader is slower but reliable.
cd build
python -m esptool --chip esp32 -p "$PORT" -b 115200 \
    --before default_reset --after hard_reset --no-stub \
    write_flash @flash_args
