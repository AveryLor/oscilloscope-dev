# Tang Nano 20K FPGA build helpers
# Requires: Gowin EDA (gw_sh) and openFPGALoader

GW_SH          ?= gw_sh
OPENFPGALOADER ?= openFPGALoader
BOARD          ?= tangnano20k

PROJ_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
GOWIN_DIR := $(PROJ_DIR)/gowin_project
SIM_DIR := $(PROJ_DIR)/sim

# Gowin typically writes the bitstream under the project impl folder
BITSTREAM ?= $(shell find $(GOWIN_DIR) -name '*.fs' 2>/dev/null | head -n 1)

.PHONY: build prog sim clean

build:
	cd $(PROJ_DIR) && $(GW_SH) build/build.tcl

prog:
	@if [ -z "$(BITSTREAM)" ]; then \
		echo "No bitstream (.fs) found under gowin_project/. Run 'make build' first."; \
		exit 1; \
	fi
	$(OPENFPGALOADER) -b $(BOARD) $(BITSTREAM)

# Run every Icarus Verilog bench (needs iverilog + vvp). Pass WAVES=1 for VCDs.
sim:
	$(MAKE) -C $(SIM_DIR) all

clean:
	rm -rf $(GOWIN_DIR) $(PROJ_DIR)/impl
	$(MAKE) -C $(SIM_DIR) clean
