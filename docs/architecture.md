# Architecture Document (Draft) — RISC-V SoC Single-Fan Controller

> This is a working draft, updated as each phase is implemented.
> Final polished version is produced at the end of the project.

## 1. Overview

The system is a small RV32I-based SoC that controls one simulated fan via
PWM, and exposes SPI and UART interfaces for configuration and status
reporting. All peripherals are memory-mapped; the core has no dedicated
I/O instructions.

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

## 3. RV32I Core (Phase 2)

Design style: **single-cycle** RV32I core.

### 3.1 Sub-blocks
- `regfile.sv` — 32 x 32-bit register file, x0 hardwired to 0.
- `alu.sv` — combinational ALU supporting RV32I ALU ops.
- `imm_gen.sv` — extracts and sign-extends immediates for I/S/B/U/J types.
- `control_unit.sv` — combinational decode of opcode/funct3/funct7 into
  control signals.
- `rv32i_core.sv` — top-level core: PC logic, instruction fetch,
  datapath wiring, memory-mapped load/store interface.

### 3.2 Instructions Supported
- R-type: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
- I-type: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI, LW, JALR
- S-type: SW
- B-type: BEQ, BNE, BLT, BGE, BLTU, BGEU
- U-type: LUI, AUIPC
- J-type: JAL
- (LB/LH/LBU/LHU/SB/SH may be added as stretch goals; core currently
  treats all loads/stores as word-aligned 32-bit for simplicity, matching
  the SRAM/peripheral register widths used in this project.)

### 3.3 Core <-> Bus Interface
Signals driven by the core on the data-memory interface:
- `dmem_addr[31:0]`
- `dmem_wdata[31:0]`
- `dmem_we`
- `dmem_re`
- `dmem_rdata[31:0]` (input)

Instruction interface:
- `imem_addr[31:0]` (= PC)
- `imem_rdata[31:0]` (input)

## 4. Status / Progress Tracker

| Phase | Item                        | Status      |
|-------|------------------------------|-------------|
| 1     | Memory map + architecture draft | Done      |
| 2     | RV32I core                   | Done        |
| 3     | Memories (IMEM/DMEM/Config)  | Pending     |
| 4     | Bus / address decoder        | Pending     |
| 5     | PWM + fan model               | Pending     |
| 6     | SPI master + slave model      | Pending     |
| 7     | UART tx/rx + terminal model    | Pending     |
| 8     | Top-level integration          | Pending     |
| 9     | Directed self-checking TB      | Pending     |
| 10    | UVM verification environment    | Pending     |
| 11    | Timing constraints (.sdc)      | Pending     |
| 12    | Final architecture document    | Pending     |
