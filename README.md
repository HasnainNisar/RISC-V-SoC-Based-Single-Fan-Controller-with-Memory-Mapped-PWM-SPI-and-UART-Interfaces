RISC-V SoC-Based Single Fan Controller with PWM, SPI, and UART
USTP Capstone Project — SystemVerilog RTL Design, UVM Verification, and FPGA Synthesis

Table of Contents
Project Overview
Directory Structure
Required Tools & Environment
How to Compile and Run Simulation
How to Run the Tests
How to Run Coverage
How to Run FPGA Synthesis (Quartus)
How to Reproduce Reported Results
Documentation
1. Project Overview
This project implements a complete RISC-V RV32I System-on-Chip (SoC) designed to control a single cooling fan. The SoC integrates:

RV32I Single-Cycle Processor Core — executes the full base integer instruction set (37 instructions)
Instruction Memory (IMEM) — 1024 × 32-bit ROM, pre-loaded from .hex file
Data SRAM (DMEM) — 1024 × 32-bit read/write RAM (4 KB)
Configuration SRAM — 64 × 32-bit (256 B) for fan profiles/thresholds, pre-loaded from config_data.hex
PWM Controller — generates variable duty-cycle signal to drive fan speed; includes stall detection and auto-retry
SPI Master — communicates with an external sensor/device (e.g. temperature sensor)
UART Interface — full-duplex serial communication for logging and diagnostics
Memory-Mapped Address Decoder — routes the core's data bus to the appropriate peripheral
Memory Map
Region	Base Address	Size	Description
IMEM	0x0000_0000	4 KB	Instruction ROM
DMEM	0x1000_0000	4 KB	Data SRAM
Config SRAM	0x2000_0000	256 B	Fan profile config
PWM Controller	0x3000_0000	256 B	PWM registers
SPI Master	0x4000_0000	256 B	SPI registers
UART	0x5000_0000	256 B	UART registers
Verification Environment
Directed Testbenches — 2 self-checking testbenches (tb_soc_top, tb_core_instr)
UVM Environment — full UVM env with agents for PWM, SPI, UART; scoreboard; 5 test cases
SVA Assertions — system-level protocol and safety assertions (soc_assertions.sv)
Code & Functional Coverage — merged UCDB + HTML report
FPGA Target
Device: Intel Cyclone IV E — EP4CE115F29C7
Tool: Quartus Prime Lite 23.1std.1
Clock: 25 MHz (timing closure achieved, Fmax ~32 MHz worst-case)
2. Directory Structure
USTP---Capstone-Project-RISC-V-SoC.../
├── README.md                        ← This file
└── soc_project/                     ← Main project root (run all tools from here)
    │
    ├── filelist.f                   ← RTL-only compile list (synthesis + lint)
    ├── constraints.sdc              ← Timing constraints (25 MHz sys_clk)
    ├── synth.tcl                    ← Legacy Quartus TCL script
    ├── modelsim.ini                 ← Questa/ModelSim library mapping
    │
    ├── run_tb.do                    ← Run directed TBs (no coverage)
    ├── run_uvm.do                   ← Run a single UVM test
    ├── run_regress.do               ← Full regression: directed + UVM + coverage
    ├── run_cov.do                   ← Merge UCDBs and generate coverage reports
    │
    ├── rtl/                         ← SYNTHESIZABLE RTL SOURCE FILES
    │   ├── soc_top.sv               ← Top-level SoC integration
    │   ├── core/
    │   │   ├── rv32i_core.sv        ← Single-cycle RV32I processor
    │   │   ├── alu.sv               ← ALU + alu_pkg
    │   │   ├── regfile.sv           ← 32×32 register file
    │   │   ├── control_unit.sv      ← Instruction decoder / control signals
    │   │   ├── imm_gen.sv           ← Immediate generator
    │   │   └── imem.sv              ← Instruction memory (ROM)
    │   ├── mem/
    │   │   ├── dmem.sv              ← Data SRAM (altsyncram in synthesis)
    │   │   └── config_sram.sv       ← Config SRAM (altsyncram in synthesis)
    │   ├── bus/
    │   │   └── addr_decoder.sv      ← Memory-mapped address decoder
    │   ├── pwm/
    │   │   └── pwm_controller.sv    ← PWM + stall/retry logic
    │   ├── spi/
    │   │   └── spi_master.sv        ← SPI master controller
    │   └── uart/
    │       ├── uart_tx.sv           ← UART transmitter FSM
    │       ├── uart_rx.sv           ← UART receiver FSM
    │       └── uart_top.sv          ← UART top (TX + RX + registers)
    │
    ├── sim/                         ← TESTBENCH & SIMULATION FILES
    │   ├── tb_filelist.f            ← Compile list: RTL + models + directed TBs
    │   ├── tb_soc_top.sv            ← Full SoC directed testbench
    │   ├── tb_core_instr.sv         ← 37-instruction RV32I core testbench
    │   ├── soc_assertions.sv        ← SystemVerilog Assertions (SVA)
    │   ├── test_program.hex         ← Firmware for SoC integration tests
    │   ├── instr_test.hex           ← RV32I instruction test program
    │   ├── instr_expected.hex       ← Golden reference for instruction test
    │   ├── config_data.hex          ← Fan profile config data
    │   └── models/                  ← Virtual peripheral models (NOT synthesizable)
    │       ├── fan_model.sv         ← Virtual fan (PWM-in → RPM-out)
    │       ├── spi_slave_model.sv   ← SPI slave device model
    │       └── uart_terminal_model.sv ← UART terminal model
    │
    ├── uvm/                         ← UVM VERIFICATION ENVIRONMENT
    │   ├── tb_filelist_uvm.f        ← Compile list for UVM environment
    │   ├── tb_top_uvm.sv            ← UVM testbench top module
    │   ├── soc_if.sv                ← SystemVerilog interface (clk, rst, DUT ports)
    │   ├── uvm_pkg_includes.sv      ← UVM package (includes all classes below)
    │   ├── env.sv                   ← UVM environment
    │   ├── scoreboard.sv            ← Self-checking scoreboard
    │   ├── core_monitor.sv          ← Core bus monitor
    │   ├── pwm_agent.sv             ← PWM agent
    │   ├── pwm_monitor.sv           ← PWM monitor
    │   ├── spi_agent.sv             ← SPI agent
    │   ├── spi_driver.sv            ← SPI driver
    │   ├── spi_monitor.sv           ← SPI monitor
    │   ├── spi_seq_item.sv          ← SPI sequence item
    │   ├── spi_sequencer.sv         ← SPI sequencer
    │   ├── uart_agent.sv            ← UART agent
    │   ├── uart_driver.sv           ← UART driver
    │   ├── uart_monitor.sv          ← UART monitor
    │   ├── uart_seq_item.sv         ← UART sequence item
    │   ├── uart_sequencer.sv        ← UART sequencer
    │   ├── test_lib.sv              ← Test library (all test classes)
    │   ├── normal_seq.sv            ← Normal operation sequence
    │   ├── error_seq.sv             ← Bus error injection sequence
    │   ├── failsafe_seq.sv          ← Fan stall/failsafe sequence
    │   └── stall_seq.sv             ← PWM stall scenario sequence
    │
    ├── cov/                         ← COVERAGE FILES & REPORTS
    │   ├── merged.ucdb              ← Merged coverage database (all tests)
    │   ├── tb_soc_top.ucdb          ← Directed TB coverage
    │   ├── tb_core_instr.ucdb       ← Instruction TB coverage
    │   ├── uvm_normal_test.ucdb     ← UVM normal test coverage
    │   ├── uvm_error_test.ucdb      ← UVM error test coverage
    │   ├── uvm_failsafe_test.ucdb   ← UVM failsafe test coverage
    │   ├── uvm_regression_test.ucdb ← UVM regression test coverage
    │   ├── uvm_core_instr_test.ucdb ← UVM instruction test coverage
    │   ├── coverage_report.txt      ← Text coverage report
    │   └── html/                    ← HTML coverage report (open index.html)
    │
    ├── tools/                       ← HELPER SCRIPTS
    │   ├── gen_programs.py          ← RV32I machine-code program generator
    │   └── rv32i_tools.py           ← RV32I assembler/disassembler utilities
    │
    ├── docs/                        ← DOCUMENTATION
    │   ├── architecture.md          ← SoC architecture overview
    │   ├── architecture_document.md ← Detailed architecture document
    │   ├── memory_map.md            ← Complete memory map reference
    │   └── synthesis_report.md      ← Quartus synthesis & timing report
    │
    └── (Quartus output files — generated by compilation)
        ├── soc_top.qpf              ← Quartus project file
        ├── soc_top.qsf              ← Quartus settings file
        ├── soc_top.flow.rpt         ← Compilation flow summary
        ├── soc_top.map.rpt          ← Analysis & Synthesis report
        ├── soc_top.fit.rpt          ← Fitter (Place & Route) report
        ├── soc_top.sta.rpt          ← Static Timing Analysis report
        └── soc_top.sof              ← FPGA bitstream
3. Required Tools & Environment
Tool	Version	Purpose
Questa Advanced Simulator	10.7+ / 2021.x+	RTL simulation, UVM, coverage
Intel Quartus Prime Lite	23.1std.1	FPGA synthesis, P&R, STA
Python	3.8+	Firmware generation scripts
Git	Any	Version control
Important: All simulation scripts must be run from the soc_project/ directory (the folder containing filelist.f, run_tb.do, etc.), NOT from the repo root.

Questa/ModelSim Setup
Questa must be on your PATH. Verify with:

vsim -version
Quartus Setup (Windows)
Quartus is installed at (example path):

D:\intelFPGA_lite\23.1std\quartus\bin64\
Either add this to your PATH, or use the full path in commands (see Section 7).

4. How to Compile and Run Simulation
All commands below must be run from soc_project/ as the working directory.

4.1 Directed Testbenches (No Coverage)
Runs both directed testbenches (tb_soc_top + tb_core_instr) sequentially:

# Inside Questa/ModelSim console:
do run_tb.do
Or from PowerShell (batch/non-interactive):

vsim -c -do "do run_tb.do; quit -f"
What it runs:

tb_soc_top — Full SoC integration tests: normal fan control, SPI reads, UART TX/RX, bus error cases, reset tests, SVA assertions
tb_core_instr — 37 RV32I instructions tested against golden ISS reference
Expected output: PASS banners for all test cases, 0 assertion failures.

5. How to Run the Tests
5.1 Single UVM Test
# In Questa console (from soc_project/):
do run_uvm.do normal_test
Available UVM tests:

Test Name	Description
normal_test	Fan speed ramp, SPI poll, UART logging — normal operation
error_test	Inject bus errors, unmapped address accesses
failsafe_test	Fan stall detection, PWM retry/failsafe mechanism
stall_seq	Extended stall scenario with timeout
regression_test	Combined regression across all scenarios
core_instr_test	Full RV32I instruction set verification via UVM
# Examples:
do run_uvm.do error_test
do run_uvm.do failsafe_test
do run_uvm.do core_instr_test   # Note: automatically loads instr_test.hex
5.2 Full Regression (All Tests)
Runs all directed TBs + all 5 UVM tests with coverage enabled:

do run_regress.do
6. How to Run Coverage
6.1 Generate Coverage During Regression
Coverage is automatically collected during run_regress.do. Individual UCDB files are saved to cov/.

6.2 Merge and Report (After Regression)
do run_cov.do
Outputs:

cov/merged.ucdb — merged coverage database
cov/coverage_report.txt — text report
cov/html/index.html — HTML report (open in browser for visual coverage)
6.3 View Existing Coverage Report
Pre-generated reports are already in cov/:

# Open HTML report in browser:
start soc_project\cov\html\index.html

# Or view text report:
Get-Content soc_project\cov\coverage_report.txt | more
7. How to Run FPGA Synthesis (Quartus)
All commands run from soc_project/ directory.

7.1 Full Compilation (Recommended)
& "D:\intelFPGA_lite\23.1std\quartus\bin64\quartus_sh.exe" --flow compile soc_top
This runs all 4 phases automatically:

Analysis & Synthesis (quartus_map)
Fitter / Place & Route (quartus_fit)
Assembler (quartus_asm) — generates soc_top.sof bitstream
Timing Analyzer (quartus_sta)
7.2 Open in Quartus GUI
Double-click soc_project/soc_top.qpf, then press Ctrl+L (Start Compilation).

7.3 Generated Reports
After compilation, these reports are in soc_project/:

File	Contents
soc_top.flow.rpt	Overall flow pass/fail summary
soc_top.map.rpt	Resource utilization by module
soc_top.fit.rpt	Place & Route details, I/O assignments
soc_top.sta.rpt	Full timing analysis, critical paths
docs/synthesis_report.md	Formatted synthesis & timing summary
8. How to Reproduce Reported Results
8.1 Simulation Results
# Step 1: Navigate to soc_project/ in Questa
# Step 2: Run full regression
do run_regress.do
# Step 3: Reports auto-generated in cov/
Expected results:

All directed TB tests: PASS
All UVM tests: 0 UVM_ERROR / UVM_FATAL
Coverage: see cov/coverage_report.txt
8.2 Synthesis Results (Quartus)
cd d:\USTP_capstone_project\USTP---Capstone-Project-RISC-V-SoC-Based-Single-Fan-Controller-with-PWM-SPI-and-UART-\soc_project

& "D:\intelFPGA_lite\23.1std\quartus\bin64\quartus_sh.exe" --flow compile soc_top
Expected results (match docs/synthesis_report.md):

Metric	Value
Flow Status	Successful — 0 Errors
Total Logic Elements	3,374 / 114,480 (3%)
Memory Bits (BRAM)	34,816 bits — altsyncram inferred
Clock	25 MHz (40 ns period)
Setup Slack (85°C worst-case)	+8.664 ns ✅
Hold Slack	All corners PASS ✅
Bitstream	soc_top.sof generated
8.3 Firmware / Hex Files
Pre-built hex files are included in sim/ and soc_project/. To regenerate:

cd soc_project\tools
python gen_programs.py
9. Documentation
All documentation is in soc_project/docs/:

Document	Description
architecture.md	SoC block diagram and architecture overview
architecture_document.md	Detailed module-level architecture document
memory_map.md	Complete memory-mapped I/O reference
synthesis_report.md	Official Quartus synthesis & timing analysis report
Quick Reference — Command Cheat Sheet
# ── SIMULATION (run from soc_project/ in Questa) ──────────────────────────
do run_tb.do                          # Directed TBs (fast, no coverage)
do run_uvm.do normal_test             # Single UVM test
do run_uvm.do error_test              # Bus error UVM test
do run_uvm.do failsafe_test           # Fan failsafe UVM test
do run_uvm.do regression_test         # UVM regression test
do run_regress.do                     # Full regression + coverage
do run_cov.do                         # Merge UCDBs + generate reports
# ── SYNTHESIS (run from soc_project/ in PowerShell) ───────────────────────
& "D:\intelFPGA_lite\23.1std\quartus\bin64\quartus_sh.exe" --flow compile soc_top
