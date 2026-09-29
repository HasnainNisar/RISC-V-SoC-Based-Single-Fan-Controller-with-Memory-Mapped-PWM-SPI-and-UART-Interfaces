## =====================================================================
## constraints.sdc - Timing Constraints for soc_top
##
## Deliverable for FINAL DELIVERABLES: "timing constraints" (per the
## project brief). Physical design (synthesis run, floorplan, CTS,
## routing, sign-off reports) is explicitly out of scope for this
## submission -- this file documents the intended timing intent only,
## so it can be handed to a synthesis/PD flow later if needed.
## =====================================================================

## -----------------------------------------------------------------
## 1. Clock definition
## -----------------------------------------------------------------
## Target: 50 MHz system clock (20 ns period), matching the clock
## used in tb_soc_top.sv / tb_top_uvm.sv. A single-cycle RV32I core
## at this frequency gives comfortable timing margin for a small
## educational design; increase CLK_PERIOD if a faster target is
## required once real synthesis timing is available.

set CLK_PORT   clk
set CLK_PERIOD 20.0   ;# ns -> 50 MHz
set CLK_UNCERTAINTY 0.5 ;# ns, jitter + skew margin

create_clock -name sys_clk -period $CLK_PERIOD [get_ports $CLK_PORT]
set_clock_uncertainty $CLK_UNCERTAINTY [get_clocks sys_clk]

## -----------------------------------------------------------------
## 2. Reset
## -----------------------------------------------------------------
## rst_n is asynchronous, active-low, and not clock-related for
## timing purposes -- exclude it from setup/hold analysis.
set_false_path -from [get_ports rst_n]

## -----------------------------------------------------------------
## 3. Input delays (external signals arriving at soc_top)
## -----------------------------------------------------------------
## SPI MISO: driven by an external slave device relative to the
## SoC's own SCLK; modeled here as a generic input relative to the
## system clock domain with generous margin (SPI runs much slower
## than the system clock due to spi_master's clock divider).
set_input_delay -clock sys_clk -max [expr {$CLK_PERIOD * 0.4}] [get_ports spi_miso]
set_input_delay -clock sys_clk -min [expr {$CLK_PERIOD * 0.1}] [get_ports spi_miso]

## UART RX: fully asynchronous to sys_clk (external host); uart_rx.sv
## already 2-flop synchronizes it internally, so treat the port itself
## as unconstrained / false-path from a static timing point of view,
## but keep a nominal input delay for basic ATPG/DFT sanity.
set_input_delay -clock sys_clk -max [expr {$CLK_PERIOD * 0.5}] [get_ports uart_rx_line]
set_false_path  -from [get_ports uart_rx_line]

## Fan tachometer feedback (RPM value from the fan/fan model). Its content only
## changes slowly (once per PWM window) but it is sampled by synchronous logic, so
## constrain it like any other synchronous input.
set_input_delay -clock sys_clk -max [expr {$CLK_PERIOD * 0.4}] [get_ports fan_rpm_in]
set_input_delay -clock sys_clk -min [expr {$CLK_PERIOD * 0.1}] [get_ports fan_rpm_in]

## -----------------------------------------------------------------
## 4. Output delays (signals leaving soc_top)
## -----------------------------------------------------------------
set_output_delay -clock sys_clk -max [expr {$CLK_PERIOD * 0.4}] [get_ports spi_sclk]
set_output_delay -clock sys_clk -max [expr {$CLK_PERIOD * 0.4}] [get_ports spi_mosi]
set_output_delay -clock sys_clk -max [expr {$CLK_PERIOD * 0.4}] [get_ports spi_cs_n]
set_output_delay -clock sys_clk -max [expr {$CLK_PERIOD * 0.4}] [get_ports uart_tx_line]

## PWM drive to the fan: a real output, constrained like the other pins
set_output_delay -clock sys_clk -max [expr {$CLK_PERIOD * 0.4}] [get_ports pwm_out]

## bus_error is a status/observability output, not timing-critical
set_false_path -to [get_ports bus_error]

## -----------------------------------------------------------------
## 5. Multicycle / false paths internal to design (documentation only)
## -----------------------------------------------------------------
## SPI and UART bit-serial engines operate on divided/derived timing
## (sclk_tick, baud_tick) generated from sys_clk inside spi_master.sv
## and uart_top.sv -- these remain synchronous to sys_clk (no separate
## clock domain is created), so no additional clock-domain-crossing
## constraints are required for this design.

## -----------------------------------------------------------------
## 6. Design rule / environment placeholders
## -----------------------------------------------------------------
## To be filled in once a target technology library is selected for
## an actual synthesis run (not performed as part of this deliverable):
##   set_max_transition <value> [current_design]
##   set_max_fanout      <value> [current_design]
##   set_driving_cell     -lib_cell <cell> [all_inputs]
##   set_load              <value> [all_outputs]
