RISC-V SoC-Based Single Fan Controller with PWM, SPI, and UART
USTP Capstone Project — SystemVerilog RTL Design, UVM Verification, and FPGA Synthesis

===============================================================================
Table of Contents
===============================================================================
1. Project Overview
2. Directory Structure
3. Required Tools & Environment
4. How to Compile and Run Simulation
5. How to Run the Tests
6. How to Run Coverage
7. How to Run FPGA Synthesis (Quartus)
8. How to Reproduce Reported Results
9. Documentation


===============================================================================
1. Project Overview
===============================================================================
This project implements a complete RISC-V RV32I System-on-Chip (SoC) designed 
to control a single cooling fan. The SoC integrates:

- RV32I Single-Cycle Processor Core (executes 37 base instructions)
- Instruction Memory (IMEM) — 1024 x 32-bit ROM (loaded from .hex)
- Data SRAM (DMEM) — 1024 x 32-bit RAM (4 KB)
- Configuration SRAM — 256 B for fan profiles (loaded from config_data.hex)
- PWM Controller — variable duty-cycle signal with stall detection / auto-retry
- SPI Master — communicates with external sensors (e.g. temperature sensor)
- UART Interface — full-duplex serial communication for diagnostics
- Memory-Mapped Address Decoder — routes data bus traffic to peripherals

Memory Map:
---------------------------------------------------------------------
Region          Base Address    Size    Description
---------------------------------------------------------------------
IMEM            0x0000_0000     4 KB    Instruction ROM
DMEM            0x1000_0000     4 KB    Data SRAM
Config SRAM     0x2000_0000     256 B   Fan profile config
PWM Controller  0x3000_0000     256 B   PWM registers
SPI Master      0x4000_0000     256 B   SPI registers
UART            0x5000_0000     256 B   UART registers

Verification Environment:
- Directed Testbenches: tb_soc_top, tb_core_instr
- UVM Environment: Scoreboard, monitors, and agents for PWM, SPI, and UART
- SVA Assertions: Protocol and safety assertions (soc_assertions.sv)
- Coverage: Combined UCDB database and visual HTML reports

FPGA Target:
- Device: Intel Cyclone IV E — EP4CE115F29C7
- Tool: Quartus Prime Lite 23.1std.1
- Clock: 25 MHz (Timing closure achieved, worst-case Fmax ~32 MHz)


===============================================================================
2. Directory Structure
===============================================================================
soc_project/                     <- Main project root directory
    |-- filelist.f               <- RTL compilation list
    |-- constraints.sdc          <- Timing constraints (25 MHz sys_clk)
    |-- run_tb.do                <- Simulation macro file for directed TBs
    |-- run_uvm.do               <- Simulation macro file for single UVM test
    |-- run_regress.do           <- Automated full regression macro file
    |-- run_cov.do               <- Automated coverage generation script
    |
    |-- rtl/                     <- Synthesizable RTL source files

    |   |-- core/                <- RV32I processor, ALU, Register File, etc.
    |   |-- mem/                 <- DMEM and Configuration SRAM models
    |   |-- bus/                 <- Memory-mapped address decoder
    |   |-- pwm/                 <- PWM driver hardware logic
    |   |-- spi/                 <- SPI Master protocol module
    |   |-- uart/                <- UART system block (TX, RX, registers)
    |
    |-- sim/                     <- Testbench infrastructure & hex binaries
    |-- uvm/                     <- Complete UVM verification framework
    |-- cov/                     <- UCDB coverage metrics & generated HTML files
    |-- tools/                   <- Program generator & assembler utilities
    |-- docs/                    <- Architecture, memory map, and timing logs


===============================================================================
3. Required Tools & Environment
===============================================================================
- Simulation: Siemens EDA QuestaSim / ModelSim (v10.g or newer)
- Synthesis: Intel Quartus Prime Lite Edition (v23.1std.1)
- Utilities: Python 3.x (for helper scripts)


===============================================================================
4. How to Compile and Run Simulation
===============================================================================
To compile the source code files and pull up the interactive simulation shell:
1. Open your terminal inside the project directory root.
2. Run the command:
   vsim -do run_tb.do


===============================================================================
5. How to Run the Tests
===============================================================================
To run individual UVM environment scenarios directly from your console:

For normal automated execution verification:
vsim -c -do "do run_uvm.do +UVM_TESTNAME=uvm_normal_test"

For fault condition processing verification:
vsim -c -do "do run_uvm.do +UVM_TESTNAME=uvm_error_test"


===============================================================================
6. How to Run Coverage
===============================================================================
To merge test traces together and generate your local web-browser dashboard:
1. Run the coverage collection script:
   vsim -c -do run_cov.do
2. Open 'soc_project/cov/html/index.html' in your browser to view the report.


===============================================================================
7. How to Run FPGA Synthesis (Quartus)
===============================================================================
1. Launch the Intel Quartus Prime desktop suite.
2. Select File -> Open Project -> Open 'soc_project/soc_top.qpf'.
3. Click Processing -> Start Compilation to run synthesis, placing, and routing.


===============================================================================
8. How to Reproduce Reported Results
===============================================================================
To run everything sequentially (compilation, all tests, regression, coverage):
vsim -c -do run_regress.do


===============================================================================
9. Documentation
===============================================================================
For specialized information, look inside the 'docs/' directory:
- Architectural Layouts: docs/architecture_document.md
- Address Definitions: docs/memory_map.md
- Hardware Cell Footprints: docs/synthesis_report.md
