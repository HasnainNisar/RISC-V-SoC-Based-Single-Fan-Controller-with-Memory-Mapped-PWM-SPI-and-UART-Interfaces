`timescale 1ns/1ps
// =====================================================================
// addr_decoder.sv - Address Decoder / Bus Interconnect
//
// Decodes the core's data-bus address (per memory_map.md) into
// individual peripheral/memory select signals, forwards we/re/wdata
// to the selected block, and muxes the correct rdata back to the core.
//
// Region decode on addr[31:28]:
//   0x0 -> Instruction SRAM (not routed here; core fetches IMEM directly)
//   0x1 -> Data SRAM
//   0x2 -> Config SRAM
//   0x3 -> Peripheral region, sub-decoded on addr[15:12]:
//            0x0 -> PWM
//            0x1 -> SPI
//            0x2 -> UART
//
// Unmapped address -> bus_error = 1, rdata = 32'hDEAD_BEEF
// (per memory_map.md Section 7).
// =====================================================================

module addr_decoder (
    input  logic         clk,
    input  logic         rst_n,

    // From core
    input  logic [31:0]  core_addr,
    input  logic [31:0]  core_wdata,
    input  logic [3:0]   core_be,      // byte enables (only SRAMs use them)
    input  logic          core_we,
    input  logic          core_re,
    output logic [31:0]  core_rdata,
    output logic          bus_error,

    // To Data SRAM
    output logic          dmem_sel,
    output logic [31:0]  dmem_addr,
    output logic [31:0]  dmem_wdata,
    output logic [3:0]   dmem_be,
    output logic          dmem_we,
    output logic          dmem_re,
    input  logic [31:0]  dmem_rdata,

    // To Config SRAM
    output logic          cfg_sel,
    output logic [31:0]  cfg_addr,
    output logic [31:0]  cfg_wdata,
    output logic [3:0]   cfg_be,
    output logic          cfg_we,
    output logic          cfg_re,
    input  logic [31:0]  cfg_rdata,

    // To PWM controller
    output logic          pwm_sel,
    output logic [31:0]  pwm_addr,
    output logic [31:0]  pwm_wdata,
    output logic          pwm_we,
    output logic          pwm_re,
    input  logic [31:0]  pwm_rdata,

    // To SPI master
    output logic          spi_sel,
    output logic [31:0]  spi_addr,
    output logic [31:0]  spi_wdata,
    output logic          spi_we,
    output logic          spi_re,
    input  logic [31:0]  spi_rdata,

    // To UART
    output logic          uart_sel,
    output logic [31:0]  uart_addr,
    output logic [31:0]  uart_wdata,
    output logic          uart_we,
    output logic          uart_re,
    input  logic [31:0]  uart_rdata
);

    // -----------------------------------------------------------------
    // Region decode
    // -----------------------------------------------------------------
    logic [3:0] region_sel;
    logic [3:0] periph_sel;

    assign region_sel = core_addr[31:28];
    assign periph_sel = core_addr[15:12];

    logic mapped;

    always_comb begin
        // Default: nothing selected
        dmem_sel  = 1'b0;
        cfg_sel   = 1'b0;
        pwm_sel   = 1'b0;
        spi_sel   = 1'b0;
        uart_sel  = 1'b0;
        mapped    = 1'b0;

        unique case (region_sel)
            4'h1: begin
                dmem_sel = 1'b1;
                mapped   = 1'b1;
            end
            4'h2: begin
                cfg_sel  = 1'b1;
                mapped   = 1'b1;
            end
            4'h3: begin
                unique case (periph_sel)
                    4'h0: begin pwm_sel  = 1'b1; mapped = 1'b1; end
                    4'h1: begin spi_sel  = 1'b1; mapped = 1'b1; end
                    4'h2: begin uart_sel = 1'b1; mapped = 1'b1; end
                    default: mapped = 1'b0;
                endcase
            end
            default: mapped = 1'b0;
        endcase
    end

    // -----------------------------------------------------------------
    // Address/data/control fan-out (all targets get full core bus;
    // only the selected one will actually act on we/re)
    // -----------------------------------------------------------------
    assign dmem_addr  = core_addr;
    assign dmem_wdata = core_wdata;
    assign dmem_be    = core_be;
    assign dmem_we    = dmem_sel & core_we;
    assign dmem_re    = dmem_sel & core_re;

    assign cfg_addr  = core_addr;
    assign cfg_wdata = core_wdata;
    assign cfg_be    = core_be;
    assign cfg_we    = cfg_sel & core_we;
    assign cfg_re    = cfg_sel & core_re;

    assign pwm_addr  = core_addr;
    assign pwm_wdata = core_wdata;
    assign pwm_we    = pwm_sel & core_we;
    assign pwm_re    = pwm_sel & core_re;

    assign spi_addr  = core_addr;
    assign spi_wdata = core_wdata;
    assign spi_we    = spi_sel & core_we;
    assign spi_re    = spi_sel & core_re;

    assign uart_addr  = core_addr;
    assign uart_wdata = core_wdata;
    assign uart_we    = uart_sel & core_we;
    assign uart_re    = uart_sel & core_re;

    // -----------------------------------------------------------------
    // Read-data mux back to core
    // -----------------------------------------------------------------
    always_comb begin
        unique case (1'b1)
            dmem_sel : core_rdata = dmem_rdata;
            cfg_sel  : core_rdata = cfg_rdata;
            pwm_sel  : core_rdata = pwm_rdata;
            spi_sel  : core_rdata = spi_rdata;
            uart_sel : core_rdata = uart_rdata;
            default  : core_rdata = 32'hDEAD_BEEF;
        endcase
    end

    // -----------------------------------------------------------------
    // Bus error: any access (we or re) to an unmapped address
    // -----------------------------------------------------------------
    logic access_active;
    assign access_active = core_we | core_re;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bus_error <= 1'b0;
        else
            bus_error <= access_active & ~mapped;
    end

endmodule
