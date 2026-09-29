// =====================================================================
// uart_monitor.sv - UART Monitor
//
// Passively watches vif.uart_tx_line (the DUT's UART transmitter
// output) and decodes each frame, publishing it on `ap` as a
// DUT_TO_HOST uart_seq_item for the scoreboard/coverage.
//
// bit_period_ns must match the DUT's configured baud rate, set via
// uvm_config_db (same as uart_driver).
// =====================================================================

`ifndef UART_MONITOR_SV
`define UART_MONITOR_SV

class uart_monitor extends uvm_monitor;

    `uvm_component_utils(uart_monitor)

    virtual soc_if vif;
    real bit_period_ns = 320.0;
    uvm_analysis_port #(uart_seq_item) ap;

    function new(string name = "uart_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif))
            `uvm_fatal("UART_MON", "Virtual interface not set for uart_monitor")
        void'(uvm_config_db#(real)::get(this, "", "bit_period_ns", bit_period_ns));
    endfunction

    task run_phase(uvm_phase phase);
        bit [7:0] byte_recv;

        forever begin
            @(negedge vif.uart_tx_line); // start bit
            #(bit_period_ns / 2.0);      // move to middle of start bit

            if (vif.uart_tx_line !== 1'b0) begin
                continue; // false start / glitch
            end

            #(bit_period_ns);
            for (int i = 0; i < 8; i++) begin
                byte_recv[i] = vif.uart_tx_line;
                #(bit_period_ns);
            end

            begin
                uart_seq_item item = uart_seq_item::type_id::create("uart_mon_item");
                item.data      = byte_recv;
                item.direction = DUT_TO_HOST;

                if (vif.uart_tx_line === 1'b1) begin
                    item.frame_error_seen = 1'b0;
                    `uvm_info("UART_MON",
                        $sformatf("Observed DUT tx byte: 0x%0h", byte_recv),
                        UVM_MEDIUM)
                end else begin
                    item.frame_error_seen = 1'b1;
                    `uvm_warning("UART_MON",
                        $sformatf("Bad stop bit on DUT tx byte: 0x%0h", byte_recv))
                end

                ap.write(item);
            end
        end
    endtask

endclass

`endif
