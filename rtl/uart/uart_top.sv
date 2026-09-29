`timescale 1ns/1ps
// =====================================================================
// uart_top.sv - UART Register Interface (wraps uart_tx + uart_rx)
//
// Register map (offsets relative to base 0x3000_2000, see memory_map.md):
//   0x0  UART_CTRL   R/W  [0]=TX_EN, [1]=RX_EN
//   0x4  UART_TXDATA W    [7:0]  byte to transmit (write triggers send)
//   0x8  UART_RXDATA R    [7:0]  last received byte
//   0xC  UART_STATUS R    [0]=TX_BUSY, [1]=RX_VALID, [2]=FRAME_ERR
//
// CLKS_PER_BIT must match the baud rate used by uart_terminal_model's
// BIT_PERIOD_NS in the testbench (BIT_PERIOD_NS = CLKS_PER_BIT * clk_period_ns).
// =====================================================================

module uart_top #(
    parameter int CLKS_PER_BIT = 868
) (
    input  logic         clk,
    input  logic         rst_n,

    // Bus interface
    input  logic          sel,
    input  logic [31:0]  addr,
    input  logic [31:0]  wdata,
    input  logic          we,
    input  logic          re,
    output logic [31:0]  rdata,

    // Serial pins
    output logic          tx_line,
    input  logic          rx_line
);

    wire [3:0] reg_offset = addr[3:0];

    // -----------------------------------------------------------------
    // Control register
    // -----------------------------------------------------------------
    logic tx_en, rx_en;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_en <= 1'b0;
            rx_en <= 1'b0;
        end else if (sel && we && (reg_offset == 4'h0)) begin
            tx_en <= wdata[0];
            rx_en <= wdata[1];
        end
    end

    // -----------------------------------------------------------------
    // Shared baud tick generator (drives uart_tx's bit timing)
    // -----------------------------------------------------------------
    localparam int BAUD_W = $clog2(CLKS_PER_BIT) + 1;
    localparam logic [BAUD_W-1:0] BAUD_LAST = BAUD_W'(CLKS_PER_BIT - 1);
    logic [BAUD_W-1:0] baud_counter;
    logic baud_tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_counter <= '0;
            baud_tick    <= 1'b0;
        end else if (baud_counter == BAUD_LAST) begin
            baud_counter <= '0;
            baud_tick    <= 1'b1;
        end else begin
            baud_counter <= baud_counter + 1'b1;
            baud_tick    <= 1'b0;
        end
    end

    // -----------------------------------------------------------------
    // Transmitter
    // -----------------------------------------------------------------
    logic [7:0] tx_data_reg;
    logic       tx_start;
    logic       tx_busy_raw, tx_busy;
    logic       tx_line_raw;

    logic       tx_start_d;
    assign tx_start = sel && we && (reg_offset == 4'h4) && tx_en;

    // Delay the start pulse by one clock: tx_data_reg is loaded on the same
    // edge that tx_start is asserted, so uart_tx must not latch tx_data until
    // the following cycle or it captures the OLD register value (0x00).
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) tx_start_d <= 1'b0;
        else        tx_start_d <= tx_start;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_data_reg <= 8'd0;
        else if (sel && we && (reg_offset == 4'h4))
            tx_data_reg <= wdata[7:0];
    end

    uart_tx u_uart_tx (
        .clk       (clk),
        .rst_n     (rst_n),
        .baud_tick (baud_tick),
        .tx_data   (tx_data_reg),
        .tx_start  (tx_start_d),
        .tx_busy   (tx_busy_raw),
        .tx_line   (tx_line_raw)
    );

    assign tx_line = tx_en ? tx_line_raw : 1'b1; // idle high when disabled
    assign tx_busy = tx_busy_raw | tx_start_d; // busy from the cycle after the write

    // -----------------------------------------------------------------
    // Receiver
    // -----------------------------------------------------------------
    logic [7:0] rx_data_reg;
    logic       rx_valid_pulse, rx_valid_sticky;
    logic       frame_err_pulse, frame_err_sticky;

    uart_rx #(
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) u_uart_rx (
        .clk         (clk),
        .rst_n       (rst_n),
        .rx_line     (rx_en ? rx_line : 1'b1),
        .rx_data     (rx_data_reg),
        .rx_valid    (rx_valid_pulse),
        .frame_error (frame_err_pulse)
    );

    // Sticky status bits, cleared when RXDATA / STATUS is read
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_valid_sticky  <= 1'b0;
            frame_err_sticky <= 1'b0;
        end else begin
            if (rx_valid_pulse)
                rx_valid_sticky <= 1'b1;
            else if (sel && re && (reg_offset == 4'h8))
                rx_valid_sticky <= 1'b0; // cleared on RXDATA read

            if (frame_err_pulse)
                frame_err_sticky <= 1'b1;
            else if (sel && re && (reg_offset == 4'hC))
                frame_err_sticky <= 1'b0; // cleared on STATUS read
        end
    end

    // -----------------------------------------------------------------
    // Read path
    // -----------------------------------------------------------------
    always_comb begin
        rdata = 32'd0;
        if (sel && re) begin
            case (reg_offset)
                4'h0: rdata = {30'd0, rx_en, tx_en};
                4'h8: rdata = {24'd0, rx_data_reg};
                4'hC: rdata = {29'd0, frame_err_sticky, rx_valid_sticky, tx_busy};
                default: rdata = 32'd0;
            endcase
        end
    end

endmodule
