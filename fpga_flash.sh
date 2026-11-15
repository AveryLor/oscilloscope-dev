#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/fpga"
make build GW_SH=~/Desktop/IDE/bin/gw_sh
openFPGALoader -b tangnano20k -f "$(find gowin_project -name '*.fs' | head -1)"
