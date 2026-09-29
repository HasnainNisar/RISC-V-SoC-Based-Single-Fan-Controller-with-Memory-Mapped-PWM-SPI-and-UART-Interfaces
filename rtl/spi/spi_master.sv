`timescale 1ns/1ps
// =====================================================================
// spi_master.sv - SPI Master Controller
//
// Register map (offsets relative to base 0x3000_1000, see memory_map.md):
//   0x0  SPI_CTRL    R/W  [0]=START, [2:1]=CLKDIV
//   0x4  SPI_TXDATA  W    [7:0]  byte to transmit (MOSI)
//   0x8  SPI_RXDATA  R    [7:0]  byte received (MISO)
//   0xC  SPI_STATUS  R    [0]=BUSY, [1]=DONE, [2]=ERROR
//
// Mode 0 SPI (CPOL=0, CPHA=0): MOSI is valid before the first SCLK rising
// edge and changes on SCLK falling edges; MISO is sampled on SCLK rising
// edges. MSB first, 8 bits per transfer.
//
// ERROR is set if a new transfer is started (START written) while a
// transfer is already in progress (BUSY) -- represents a misuse /
// protocol-violation error case for verification.
// =====================================================================

module spi_master (
    input  logic         clk,
    input  logic         rst_n,

    // Bus interface
    input  logic          sel,
    input  logic [31:0]  addr,
    input  logic [31:0]  wdata,
    input  logic          we,
    input  logic          re,
    output logic [31:0]  rdata,

    // SPI pins
    output logic          sclk,
    output logic          mosi,
    input  logic          miso,
    output logic          cs_n
);

    wire [3:0] reg_offset = addr[3:0];

    // -----------------------------------------------------------------
    // Registers
    // -----------------------------------------------------------------
    logic [1:0] clkdiv_reg;
    logic [7:0] tx_data_reg;
    logic [7:0] rx_data_reg;
    logic       start_pulse;
    logic       busy_reg, done_reg, error_reg;

    // START is a write-1-pulses-a-transfer style bit; we detect the
    // write itself rather than storing a persistent "start" level.
    assign start_pulse = sel && we && (reg_offset == 4'h0) && wdata[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clkdiv_reg  <= 2'b00;
            tx_data_reg <= 8'd0;
        end else if (sel && we) begin
            case (reg_offset)
                4'h0: clkdiv_reg  <= wdata[2:1];
                4'h4: tx_data_reg <= wdata[7:0];
                default: ;
            endcase
        end
    end

    // -----------------------------------------------------------------
    // Clock divider -> generates sclk_tick (one pulse per half SCLK period)
    // -----------------------------------------------------------------
    logic [7:0] div_counter;
    logic       sclk_tick;
    logic [7:0] div_max;

    always_comb begin
        case (clkdiv_reg)
            2'b00: div_max = 8'd1;   // fastest
            2'b01: div_max = 8'd3;
            2'b10: div_max = 8'd7;
            2'b11: div_max = 8'd15;  // slowest
            default: div_max = 8'd1;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_counter <= 8'd0;
            sclk_tick   <= 1'b0;
        end else if (busy_reg) begin
            if (div_counter == div_max) begin
                div_counter <= 8'd0;
                sclk_tick   <= 1'b1;
            end else begin
                div_counter <= div_counter + 8'd1;
                sclk_tick   <= 1'b0;
            end
        end else begin
            div_counter <= 8'd0;
            sclk_tick   <= 1'b0;
        end
    end

    // -----------------------------------------------------------------
    // FSM: IDLE -> CS_ASSERT -> TRANSFER (16 half-edges = 8 bits) -> DONE
    // -----------------------------------------------------------------
    typedef enum logic [1:0] {S_IDLE, S_TRANSFER, S_DONE} spi_state_e;
    spi_state_e state, state_next;

    logic [3:0] bit_count;     // counts 0-7 bits shifted
    logic       sclk_reg;
    logic [7:0] shift_out;
    logic [7:0] shift_in;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            busy_reg    <= 1'b0;
            done_reg    <= 1'b0;
            error_reg   <= 1'b0;
            cs_n        <= 1'b1;
            mosi        <= 1'b0;
            sclk_reg    <= 1'b0;
            bit_count   <= 4'd0;
            shift_out   <= 8'd0;
            shift_in    <= 8'd0;
            rx_data_reg <= 8'd0;
        end else begin
            // DONE flag clears automatically once STATUS is read, or on new start
            if (sel && re && (reg_offset == 4'hC))
                done_reg <= 1'b0;

            // START written while a transfer is in progress -> protocol error.
            // (Must be checked outside S_IDLE: in S_IDLE the master is by
            // definition not busy, so the old check there was dead code.)
            if (start_pulse && (state != S_IDLE))
                error_reg <= 1'b1;

            case (state)
                S_IDLE: begin
                    cs_n     <= 1'b1;
                    sclk_reg <= 1'b0;
                    if (start_pulse) begin
                        busy_reg  <= 1'b1;
                        error_reg <= 1'b0;
                        cs_n      <= 1'b0;
                        shift_out <= tx_data_reg;
                        mosi      <= tx_data_reg[7]; // MSB valid BEFORE first SCLK rising edge (Mode 0)
                        bit_count <= 4'd0;
                        state     <= S_TRANSFER;
                    end
                end

                S_TRANSFER: begin
                    if (sclk_tick) begin
                        if (sclk_reg == 1'b0) begin
                            // Rising edge: sample MISO (Mode 0, CPHA=0)
                            sclk_reg <= 1'b1;
                            shift_in <= {shift_in[6:0], miso};
                        end else begin
                            // Falling edge: shift and present next MOSI bit
                            sclk_reg  <= 1'b0;
                            shift_out <= {shift_out[6:0], 1'b0};
                            mosi      <= (bit_count == 4'd7) ? 1'b0 : shift_out[6];
                            if (bit_count == 4'd7)
                                state <= S_DONE;
                            else
                                bit_count <= bit_count + 4'd1;
                        end
                    end
                end

                S_DONE: begin
                    cs_n        <= 1'b1;
                    busy_reg    <= 1'b0;
                    done_reg    <= 1'b1;
                    rx_data_reg <= shift_in;
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign sclk = sclk_reg;

    // -----------------------------------------------------------------
    // Read path
    // -----------------------------------------------------------------
    always_comb begin
        rdata = 32'd0;
        if (sel && re) begin
            case (reg_offset)
                4'h0: rdata = {29'd0, clkdiv_reg, 1'b0};
                4'h8: rdata = {24'd0, rx_data_reg};
                4'hC: rdata = {29'd0, error_reg, done_reg, busy_reg};
                default: rdata = 32'd0;
            endcase
        end
    end

endmodule
