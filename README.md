# Oscilloscope

FPGA + ESP32 firmware for an oscilloscope: the Tang Nano 20K buffers ADC samples; an ESP32 streams them to a laptop for display.

## Hardware

- Sipeed Tang Nano 20K (GW2AR-18C)
- ESP32 NodeMCU-32S (laptop link)

## System architecture

| Block | Role |
|-------|------|
| **FPGA** | Sample ADC at encode clock, run trigger + circular capture buffer, freeze on trigger, SPI slave readout |
| **ESP32** | SPI master, register/control plane, stream frozen captures to the PC over USB-UART |

Dataflow is **freeze-mode / single-shot**: the FPGA always fills a ring buffer; a trigger decides when to stop; the ESP32 then dumps the frozen window. It is not a continuous 100 Msps pipe to the laptop.

## Pinout

### ADC → Tang Nano 20K (left header)

Cluster data on the left header; put encode clock on global-clock-capable pin `77` (`GCLKT_1`).

| Signal | Nano header | FPGA pin | Notes |
|--------|-------------|----------|-------|
| `ADC_ENC_CLK` | Left 5 | 77 | GCLK; clocking / termination priority |
| `ADC_D0` | Left 8 | 27 | |
| `ADC_D1` | Left 9 | 28 | |
| `ADC_D2` | Left 10 | 25 | |
| `ADC_D3` | Left 11 | 26 | |
| `ADC_D4` | Left 12 | 29 | |
| `ADC_D5` | Left 13 | 30 | |
| `ADC_D6` | Left 14 | 31 | |
| `ADC_D7` | Left 15 | 17  |
| `ADC_D8` | Left 16 | 20 | LED5 silk |
| `ADC_D9` | Left 17 | 19 | LED4 silk |
| `ADC_OR` | Left 18 | 18 | LED3 silk |
| `EXT_TRIG` | Left 4 | 85 | External hardware trigger input |
| GND | Left 20, Right 2, Right 15 | — | Extra GND returns to the ADC board |

Signal integrity on the ADC header: series ~22–33 Ω at the ADC data drivers, many GND returns interleaved with data, short stack headers preferred over ribbon.

### ESP32 ↔ FPGA (SPI + handshake, right header)

ESP32 is SPI master (VSPI); FPGA is SPI slave. Prefer SPI over I2C for capture readout.

| Signal | ESP32 GPIO | NodeMCU silk | Nano header | FPGA pin | Dir |
|--------|------------|--------------|-------------|----------|-----|
| `SPI_SCLK` | 18 | P18 | Right 3 | 76 | ESP → FPGA |
| `SPI_MOSI` | 23 | P23 | Right 17 | 72 | ESP → FPGA |
| `SPI_MISO` | 19 | P19 | Right 18 | 71 | FPGA → ESP |
| `SPI_CS` | 5 | P5 | Right 13 | 86 | ESP → FPGA |
| `FPGA_IRQ` | 16 | P16 | Right 19 | 53 | FPGA → ESP (capture ready) |
| `FPGA_RST` | 17 | P17 | Right 20 | 52 | ESP → FPGA (soft reset / re-arm) |
| GND | any GND | GND | Right 2 / 15 | — | Common ground required |

Other constraints:

- Expect **capture → freeze → SPI dump → display**, not continuous roll at full sample rate (roll/decimation can run in the FPGA at a reduced rate).
- Deep memory and high UI refresh want a USB FIFO later; ESP32 is fine for bring-up, control plane, and modest capture depths.


## Repository layout

| Path | Role |
|------|------|
| `fpga/` | Tang Nano 20K RTL, constraints, Gowin build |
| `esp32/` | ESP-IDF firmware (streamer) |

## Build

**FPGA** (needs [Gowin EDA](https://www.gowinsemi.com/) `gw_sh` and [openFPGALoader](https://github.com/trabucayre/openFPGALoader)):

```bash
make -C fpga/ build
make -C fpga/ prog
```

**ESP32** (needs [ESP-IDF](https://docs.espressif.com/projects/esp-idf/)):

```bash
cd esp32
idf.py set-target esp32
idf.py build
idf.py flash monitor
```

## Branch protection (`main`)

Direct pushes and force pushes to `main` are not allowed. Work on a branch and open a pull request:

```bash
git checkout -b my-change
git push -u origin HEAD
# open a PR into main, then merge on GitHub
```

Enforcement is a GitHub **repository ruleset** (not Actions alone). The policy lives in [`.github/rulesets/main.json`](.github/rulesets/main.json).

### One-time ruleset setup

1. Create a fine-grained PAT with **Administration: Read and write** for this repository.
2. Add it as a repository secret named `RULESET_TOKEN`.
3. Run the **Apply main ruleset** workflow (`workflow_dispatch`), or apply locally:

```bash
export RULESET_TOKEN=...   # same PAT
export GITHUB_REPOSITORY=AveryLor/oscilloscope-dev
./.github/scripts/apply-main-ruleset.sh
```

Repository admins can bypass the ruleset for break-glass only. [`.github/workflows/guard-main.yml`](.github/workflows/guard-main.yml) also fails the Actions run if a forced push to `main` is ever observed.
