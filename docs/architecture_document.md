# Architecture Document — RISC-V SoC-Based Single-Fan Controller

## 1. Objective Recap

An RV32I-based SoC that drives one simulated fan via PWM, and exposes
SPI and UART interfaces for configuration and status reporting.
Configuration values (fan profiles/thresholds) are held in on-chip
SRAM. This document covers RTL design, SRAM integration, basic
self-checking simulation, timing constraints, and UVM verification.
**Physical design (synthesis run, floorplan, CTS, routing, sign-off
reports, layout screenshots) is explicitly out of scope for this
submission.**

## 2. Top-Level Block Diagram

```
                     ┌─────────────────────────┐
                     │      RV32I CORE          │
                     │  (single-cycle)          │
                     └───────┬─────────┬────────┘
                             │         │
                       Instr Bus     Data Bus
                             │         │
               ┌─────────────┘         └──────────────┐
               │                                       │
       ┌───────▼────────┐                    ┌─────────▼─────────┐
       │  Instruction     │                    │   Address Decoder │
       │  SRAM (IMEM)     │                    └──┬───┬───┬───┬────┘
       └──────────────────┘                       │   │   │   │
                                          ┌────────┘   │   │   └─────────┐
                                          │             │   │            │
                                   ┌──────▼───┐  ┌──────▼─┐ ┌▼────────┐ ┌▼─────────┐
                                   │ Data SRAM │  │ Config │ │  PWM    │ │ SPI Master│
                                   │ (DMEM)    │  │ SRAM   │ │ Ctrl    │ │           │
                                   └───────────┘  └────────┘ └────┬────┘ └────┬─────┘
                                                                    │           │
                                                              ┌─────▼───┐  ┌────▼────┐
                                                              │Fan Model│  │SPI Slave│
                                                              │(virtual)│  │ Model   │
                                                              └─────────┘  └─────────┘
                                          ┌──────────┐
                                          │  UART    │
                                          │ Tx/Rx    │──── UART Terminal Model
                                          └──────────┘
```

`spi_slave_model` and `uart_terminal_model` are testbench-side only —
they are not part of the synthesizable `soc_top` DUT.

## 3. RV32I Core

Single-cycle datapath (`rtl/core/rv32i_core.sv`) built from:
`regfile.sv`, `alu.sv` (+ `alu_pkg`), `imm_gen.sv`, `control_unit.sv`.

Supported instructions: R-type (ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/
SLT/SLTU), I-type (ADDI/ANDI/ORI/XORI/SLTI/SLTIU/SLLI/SRLI/SRAI/
LW/JALR), S-type (SW), B-type (BEQ/BNE/BLT/BGE/BLTU/BGEU), U-type
(LUI/AUIPC), J-type (JAL). All loads/stores are word-aligned 32-bit
(LW/SW only), matching the 32-bit width of every SRAM and peripheral
register in this design.

## 4. Memory Map

See `docs/memory_map.md` for the full register-level detail.
Summary:

| Region          | Base Address  | Size  |
|------------------|----------------|-------|
| Instruction SRAM  | 0x0000_0000    | 4 KB  |
| Data SRAM          | 0x1000_0000    | 4 KB  |
| Config SRAM         | 0x2000_0000    | 256 B |
| PWM Controller       | 0x3000_0000    | 16 B  |
| SPI Master            | 0x3000_1000    | 16 B  |
| UART Tx/Rx              | 0x3000_2000    | 16 B  |

Address decoding (`rtl/bus/addr_decoder.sv`) uses `addr[31:28]` for
top-level region select and `addr[15:12]` to sub-select within the
peripheral region. Unmapped accesses assert `bus_error`.

## 5. Peripherals

### 5.1 PWM Fan Controller (`rtl/pwm/pwm_controller.sv`)
Free-running 8-bit counter + comparator generates the PWM waveform
(`pwm_out = counter < duty_reg`). A stall counter flags `FAULT` if the
fan model reports `rpm_in == 0` for `STALL_CYCLES` while enabled
(jammed/disconnected-fan detection).

### 5.2 Virtual Fan Model (`rtl/pwm/fan_model.sv`)
Behavioral, testbench/simulation-only model. Measures `pwm_out`'s duty
over a 256-cycle window, computes a proportional target RPM, and ramps
the reported RPM toward that target (spin-up/spin-down inertia). A
`stall_inject` input lets tests force a jammed-fan condition.

### 5.3 SPI Master (`rtl/spi/spi_master.sv`)
Mode 0 (CPOL=0, CPHA=0), 8-bit transfers, MSB-first, configurable
clock divider. Asserts `ERROR` if `START` is written while a transfer
is already in progress. `spi_slave_model.sv` (testbench-side) plays
the role of an external "smart fan module" supplying profile bytes.

### 5.4 UART (`rtl/uart/uart_tx.sv`, `uart_rx.sv`, `uart_top.sv`)
Standard 8N1 framing (1 start, 8 data LSB-first, 1 stop, no parity).
Receiver uses mid-bit sampling with a 2-flop input synchronizer and
flags `FRAME_ERR` on a missing stop bit. `uart_terminal_model.sv`
(testbench-side) represents an external host/terminal.

## 6. Top-Level Integration

`rtl/soc_top.sv` instantiates and wires the core, IMEM, address
decoder, DMEM, config SRAM, PWM controller + fan model, SPI master,
and UART, exposing external SPI/UART pins plus debug/observability
outputs (`bus_error`, `fan_rpm_debug`, `pwm_out_debug`) and a
`fan_stall_inject` test-control input.

## 7. Verification Strategy

### 7.1 Basic Directed Self-Checking Testbench (`sim/tb_soc_top.sv`)
- **Part A** (full-SoC, program-driven): runs a hand-assembled RV32I
  program (`sim/test_program.hex`) through reset and normal operation
  — SRAM write/read, PWM enable + duty configuration, an SPI transfer
  against `spi_slave_model`, and a UART transmit observed by
  `uart_terminal_model`. Checked with `check_equal`/`check_true` tasks
  against expected values.
- **Part B** (directed error cases, unit-level): separately
  instantiated peripheral modules driven directly by the testbench to
  exercise conditions awkward to reach via hand-written assembly —
  PWM stall/fault detection, SPI start-while-busy protocol error, and
  UART framing error.
- A final PASS/FAIL summary with counts is printed; a global timeout
  guards against a stuck wait loop.

### 7.2 UVM Verification Environment (`uvm/`)
- **Agents**: `spi_agent` (driver plays the external SPI slave role;
  monitor observes every transfer), `uart_agent` (driver plays an
  external host sending bytes; monitor decodes DUT-transmitted
  bytes), `pwm_agent` (passive-only monitor sampling duty/RPM/fault
  once per PWM window).
- **Scoreboard** (`uvm/scoreboard.sv`): protocol-level checks plus
  functional coverage covergroups (SPI byte-value bins, UART
  data-value bins + frame-error bin, PWM duty-cycle bins crossed with
  fault occurrence).
- **Sequences**: `normal_seq` (profile load / host commands),
  `error_seq` (unresponsive SPI slave, malformed UART frame),
  `stall_seq` / `failsafe_seq` (fan-jam injection and recovery,
  checking that `FAULT` both asserts and later clears).
- **Tests** (`uvm/test_lib.sv`): `normal_test`, `error_test`,
  `failsafe_test`, `regression_test`.
- Code coverage (line/branch/toggle/FSM) is collected by the
  simulator's built-in coverage tooling when enabled at compile time;
  no additional RTL/TB instrumentation is required for that.
- Requires a UVM-1.2-capable simulator (Questa/VCS/Xcelium); Icarus
  Verilog's UVM support is not sufficient for Phase 10.

## 8. Timing Constraints

`constraints.sdc` defines a 50 MHz system clock (matching the
testbench), false-paths for the asynchronous reset and UART RX input,
input/output delay budgets for the SPI/UART pins, and placeholders for
technology-specific environment constraints (max transition, fanout,
driving cell, output load) to be filled in once a target library is
selected for an actual synthesis run.

## 9. Known Limitations / Simplifications

- Core is single-cycle; no pipelining, caching, or MMU, per the
  project scope.
- Only word-aligned LW/SW are implemented (no byte/halfword
  loads/stores), since every memory and peripheral register in this
  design is 32-bit.
- RTL and hand-assembled test program were authored without access to
  a SystemVerilog simulator or RISC-V toolchain in the authoring
  environment; first compilation on the reader's own simulator may
  surface minor syntax or encoding issues to debug.
- Physical design (synthesis, floorplan, power plan, placement, CTS,
  routing, DRC/LVS, area/timing/power/congestion reports, layout
  screenshots) is out of scope for this submission by request.

## 10. File Index

| Phase | Contents | Location |
|-------|-----------|----------|
| 1  | Memory map, architecture draft | `docs/` |
| 2  | RV32I core                     | `rtl/core/` |
| 3  | IMEM, DMEM, Config SRAM         | `rtl/core/imem.sv`, `rtl/mem/` |
| 4  | Address decoder                 | `rtl/bus/addr_decoder.sv` |
| 5  | PWM controller + fan model       | `rtl/pwm/` |
| 6  | SPI master + slave model          | `rtl/spi/` |
| 7  | UART tx/rx/top + terminal model    | `rtl/uart/` |
| 8  | Top-level integration + filelist    | `rtl/soc_top.sv`, `filelist.f` |
| 9  | Directed self-checking TB + program   | `sim/` |
| 10 | UVM verification environment           | `uvm/` |
| 11 | Timing constraints                      | `constraints.sdc` |
| 12 | This document                            | `docs/architecture_document.md` |

## 11. How to Run

**Basic testbench (Icarus Verilog or any SV simulator):**
```
cd sim
iverilog -g2012 -f tb_filelist.f -o tb_sim
vvp tb_sim
```

**UVM environment (Questa example):**
```
cd uvm
vlog -sv +incdir+. -f tb_filelist_uvm.f
vsim -c work.tb_top_uvm +UVM_TESTNAME=normal_test -do "run -all; quit"
```
Copy `sim/test_program.hex` and `sim/config_data.hex` into the run
directory first (referenced via relative path in `soc_top`'s
`IMEM_INIT_FILE`/`CFG_INIT_FILE` parameters).
