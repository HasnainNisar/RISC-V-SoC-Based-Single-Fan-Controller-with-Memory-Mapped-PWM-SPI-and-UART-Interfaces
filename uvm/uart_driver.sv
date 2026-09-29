// =====================================================================
// uart_driver.sv - UART Driver
//
// Plays the role of the external terminal/host: drives correctly
// (or, for error-case items, incorrectly) framed bytes onto
// vif.uart_rx_line, which feeds the DUT's UART receiver.
//
// bit_period_ns must be set via uvm_config_db to match the DUT's
// configured baud rate (CLKS_PER_BIT * clk_period_ns in uart_top.sv).
// =====================================================================

`ifndef UART_DRIVER_SV
`define UART_DRIVER_SV

class uart_driver extends uvm_driver #(uart_seq_item);

    `uvm_component_utils(uart_driver)

    virtual soc_if vif;
    real bit_period_ns = 320.0; // default, overridden via config_db

    // Publishes every host->DUT item after it has been sent (for scoreboard receive checks)
    uvm_analysis_port #(uart_seq_item) exp_ap;

    function new(string name = "uart_driver", uvm_component parent = null);
        super.new(name, parent);
        exp_ap = new("exp_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif))
            `uvm_fatal("UART_DRV", "Virtual interface not set for uart_driver")
        void'(uvm_config_db#(real)::get(this, "", "bit_period_ns", bit_period_ns));
    endfunction

    task run_phase(uvm_phase phase);
        vif.uart_rx_line <= 1'b1; // idle high

        forever begin
            uart_seq_item req;
            seq_item_port.get_next_item(req);

            if (req.direction == HOST_TO_DUT) begin
                send_byte(req.data, req.inject_bad_stop_bit);
                exp_ap.write(req);
                `uvm_info("UART_DRV",
                    $sformatf("Sent byte 0x%0h to DUT (bad_stop=%0b)",
                              req.data, req.inject_bad_stop_bit),
                    UVM_MEDIUM)
            end
            // DUT_TO_HOST items are not driven; the monitor observes
            // those passively. Just complete the item.

            seq_item_port.item_done();
        end
    endtask

    task automatic send_byte(input [7:0] data, input bit bad_stop_bit);
        vif.uart_rx_line <= 1'b0; // start bit
        #(bit_period_ns);
        for (int i = 0; i < 8; i++) begin
            vif.uart_rx_line <= data[i]; // LSB first
            #(bit_period_ns);
        end
        vif.uart_rx_line <= bad_stop_bit ? 1'b0 : 1'b1; // stop bit (or deliberately bad)
        #(bit_period_ns);
        vif.uart_rx_line <= 1'b1; // back to idle
    endtask

endclass

`endif
