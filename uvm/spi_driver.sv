// =====================================================================
// spi_driver.sv - SPI Driver
//
// The DUT's spi_master is always the SPI *master*. This driver plays
// the role of the external SPI *slave* (the "smart fan module"),
// consuming spi_seq_item transactions from the sequencer and driving
// MISO accordingly, while capturing what the DUT sent on MOSI.
//
// Edge convention (Mode 0, matches spi_master.sv / spi_slave_model.sv):
//   - Slave drives MISO on SCLK falling edge (setup for master's
//     next high phase).
//   - Slave samples MOSI on SCLK rising edge.
// =====================================================================

`ifndef SPI_DRIVER_SV
`define SPI_DRIVER_SV

class spi_driver extends uvm_driver #(spi_seq_item);

    `uvm_component_utils(spi_driver)

    virtual soc_if vif;
    real cs_timeout_ns = 100_000.0; // give up on an item if the DUT starts no SPI transfer in this time

    // Publishes each item at the moment the DUT actually starts the transfer, so the
    // scoreboard knows what response the slave was supposed to give.
    uvm_analysis_port #(spi_seq_item) exp_ap;

    function new(string name = "spi_driver", uvm_component parent = null);
        super.new(name, parent);
        exp_ap = new("exp_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif))
            `uvm_fatal("SPI_DRV", "Virtual interface not set for spi_driver")
    endfunction

    task run_phase(uvm_phase phase);
        spi_seq_item req;
        bit [7:0] tx_shift, rx_shift;
        bit       got_cs;

        vif.spi_miso <= 1'b0;

        forever begin
            seq_item_port.get_next_item(req);

            // Wait for the DUT to assert CS (start of a transfer) -- but do
            // not hang forever: test_program.hex performs only ONE SPI
            // transfer, so any further items would otherwise block the
            // sequence (and the test's objection) until the global timeout.
            got_cs = 1'b0;
            fork
                begin @(negedge vif.spi_cs_n); got_cs = 1'b1; end
                begin #(cs_timeout_ns); end
            join_any
            disable fork;

            if (!got_cs) begin
                `uvm_warning("SPI_DRV",
                    $sformatf("No SPI transfer started by DUT within %0.0f ns; dropping item", cs_timeout_ns))
                seq_item_port.item_done();
                continue;
            end

            exp_ap.write(req);

            tx_shift = req.resp_byte;
            rx_shift = 8'd0;

            // Mode 0: MSB must already be on MISO before the first SCLK
            // rising edge, so drive it as soon as CS asserts.
            vif.spi_miso <= req.inject_no_response ? 1'b0 : tx_shift[7];

            fork
                begin : drive_miso
                    forever begin
                        @(negedge vif.spi_sclk or posedge vif.spi_cs_n);
                        if (vif.spi_cs_n) disable drive_miso;
                        tx_shift = {tx_shift[6:0], 1'b0};   // advance to next bit...
                        vif.spi_miso <= req.inject_no_response ? 1'b0 : tx_shift[7]; // ...and present it
                    end
                end
                begin : sample_mosi
                    forever begin
                        @(posedge vif.spi_sclk or posedge vif.spi_cs_n);
                        if (vif.spi_cs_n) disable sample_mosi;
                        rx_shift = {rx_shift[6:0], vif.spi_mosi};
                    end
                end
                begin : wait_cs_done
                    @(posedge vif.spi_cs_n);
                end
            join_any
            disable fork;

            vif.spi_miso <= 1'b0;   // idle MISO low between transfers

            req.mosi_byte = rx_shift;
            req.miso_byte = req.resp_byte;

            `uvm_info("SPI_DRV",
                $sformatf("Transfer done: sent=0x%0h received=0x%0h no_resp=%0b",
                          req.resp_byte, req.mosi_byte, req.inject_no_response),
                UVM_MEDIUM)

            seq_item_port.item_done();
        end
    endtask

endclass

`endif
