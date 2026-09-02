# Icarus Verilog test benches for the Tang Nano 20K oscilloscope RTL.
# Each tb_*.sv is compiled against the whole RTL tree plus the behavioral models
# and run with vvp. Usage:
#   make            run every bench
#   make tb_trigger_engine
#   make WAVES=1 tb_top     also write build/<name>.vcd
#   make clean

IVERILOG ?= iverilog
VVP      ?= vvp

IFLAGS := -g2012 -Wall -Wno-timescale -I../rtl -I../rtl/cdc -I../rtl/common -I../rtl/video -I. -Imodels

# scope_pkg.sv and video_pkg.sv must come first so the packages are defined
# before any module imports them.
RTL_ALL := $(wildcard ../rtl/*.sv ../rtl/*.v ../rtl/cdc/*.sv ../rtl/common/*.sv \
                      ../rtl/video/*.sv ../rtl/video/*.v)
RTL     := ../rtl/scope_pkg.sv ../rtl/video/video_pkg.sv \
           $(filter-out ../rtl/scope_pkg.sv ../rtl/video/video_pkg.sv,$(RTL_ALL))
MODELS  := $(wildcard models/*.v models/*.sv)

TBS := $(basename $(notdir $(wildcard tb_*.sv)))

ifdef WAVES
IFLAGS += -DDUMP_VCD
endif

.PHONY: all clean $(TBS)

all: $(TBS)
	@echo "---- all benches run ----"

$(TBS): tb_%: tb_%.sv $(RTL) $(MODELS) tb_common.svh
	@mkdir -p build
	@$(IVERILOG) $(IFLAGS) -s $@ -o build/$@.vvp $(RTL) $(MODELS) $<
	@$(VVP) -n build/$@.vvp

clean:
	rm -rf build
