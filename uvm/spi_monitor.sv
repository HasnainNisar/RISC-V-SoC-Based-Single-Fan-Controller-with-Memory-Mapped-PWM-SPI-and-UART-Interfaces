// =====================================================================
// spi_monitor.sv - SPI Monitor
//
// Passively watches spi_sclk/spi_mosi/spi_miso/spi_cs_n and
// reconstructs each completed 8-bit transfer, publishing it on
// `ap` (analysis port) for the scoreboard and coverage collector.
// =====================================================================

`ifndef SPI_MONITOR_SV
`define SPI_MONITOR_SV

class spi_monitor extends uvm_monitor;

    `uvm_component_utils(spi_monitor)

    virtual soc_if vif;
    uvm_analysis_port #(spi_seq_item) ap;

    function new(string name = "spi_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif))
            `uvm_fatal("SPI_MON", "Virtual interface not set for spi_monitor")
    endfunction

    task run_phase(uvm_phase phase);
        bit [7:0] mosi_shift, miso_shift;

        forever begin
            @(negedge vif.spi_cs_n); // transfer starts
            mosi_shift = 8'd0;
            miso_shift = 8'd0;

            for (int i = 0; i < 8; i++) begin
                @(posedge vif.spi_sclk or posedge vif.spi_cs_n);
                if (vif.spi_cs_n) break; // aborted early
                mosi_shift = {mosi_shift[6:0], vif.spi_mosi};
                miso_shift = {miso_shift[6:0], vif.spi_miso};
            end

            begin
                spi_seq_item item = spi_seq_item::type_id::create("spi_mon_item");
                item.mosi_byte = mosi_shift;
                item.miso_byte = miso_shift;
                `uvm_info("SPI_MON",
                    $sformatf("Observed transfer: mosi=0x%0h miso=0x%0h",
                              mosi_shift, miso_shift),
                    UVM_HIGH)
                ap.write(item);
            end

            // Wait for CS to actually go high before looking for the
            // next transfer's falling edge.
            wait (vif.spi_cs_n === 1'b1);
        end
    endtask

endclass

`endif
