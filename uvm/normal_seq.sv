// =====================================================================
// normal_seq.sv - Normal-Operation Sequences
//
// spi_normal_seq : responds to each DUT-initiated SPI transfer with a
//                  sequence of profile bytes (mirrors the fan-profile
//                  read use case from architecture.md).
// uart_normal_seq: sends a set of well-formed command bytes to the
//                  DUT as a host/terminal would.
// =====================================================================

`ifndef NORMAL_SEQ_SV
`define NORMAL_SEQ_SV

class spi_normal_seq extends uvm_sequence #(spi_seq_item);

    `uvm_object_utils(spi_normal_seq)

    bit [7:0] profile_bytes[] = '{8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'h11, 8'h22};

    // test_program.hex performs 4 SPI transfers (profile loading: 4 bytes ->
    // DMEM[1..4] and config SRAM[0..3]); one response is queued for each.
    int unsigned num_transfers = 4;

    function new(string name = "spi_normal_seq");
        super.new(name);
    endfunction

    task body();
        for (int i = 0; i < num_transfers && i < profile_bytes.size(); i++) begin
            spi_seq_item req = spi_seq_item::type_id::create("req");
            start_item(req);
            req.resp_byte          = profile_bytes[i];
            req.inject_no_response = 1'b0;
            finish_item(req);
            `uvm_info("SPI_NORMAL_SEQ",
                $sformatf("Responded with profile byte 0x%0h", profile_bytes[i]),
                UVM_MEDIUM)
        end
    endtask

endclass

class uart_normal_seq extends uvm_sequence #(uart_seq_item);

    `uvm_object_utils(uart_normal_seq)

    bit [7:0] cmd_bytes[] = '{8'h50, 8'h64, 8'h01}; // e.g. "SET_DUTY", value, "ACTIVATE"

    function new(string name = "uart_normal_seq");
        super.new(name);
    endfunction

    task body();
        foreach (cmd_bytes[i]) begin
            uart_seq_item req = uart_seq_item::type_id::create("req");
            start_item(req);
            req.data                 = cmd_bytes[i];
            req.direction             = HOST_TO_DUT;
            req.inject_bad_stop_bit  = 1'b0;
            finish_item(req);
            `uvm_info("UART_NORMAL_SEQ",
                $sformatf("Sent command byte 0x%0h to DUT", cmd_bytes[i]),
                UVM_MEDIUM)
        end
    endtask

endclass

`endif
