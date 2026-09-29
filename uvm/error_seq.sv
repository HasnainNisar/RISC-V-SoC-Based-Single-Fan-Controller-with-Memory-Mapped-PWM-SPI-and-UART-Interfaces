// =====================================================================
// error_seq.sv - Error-Case Sequences
//
// spi_error_seq : the "slave" never responds on MISO (disconnected /
//                 unresponsive fan module) -- exercises the DUT's
//                 handling of an incomplete/garbage SPI response.
// uart_error_seq: sends a byte with a deliberately bad stop bit
//                 (framing error case).
// =====================================================================

`ifndef ERROR_SEQ_SV
`define ERROR_SEQ_SV

class spi_error_seq extends uvm_sequence #(spi_seq_item);

    `uvm_object_utils(spi_error_seq)

    function new(string name = "spi_error_seq");
        super.new(name);
    endfunction

    task body();
        spi_seq_item req = spi_seq_item::type_id::create("req");
        start_item(req);
        req.resp_byte          = 8'h00;
        req.inject_no_response = 1'b1; // unresponsive slave
        finish_item(req);
        `uvm_info("SPI_ERROR_SEQ", "Issued transfer with no slave response", UVM_MEDIUM)
    endtask

endclass

class uart_error_seq extends uvm_sequence #(uart_seq_item);

    `uvm_object_utils(uart_error_seq)

    function new(string name = "uart_error_seq");
        super.new(name);
    endfunction

    task body();
        uart_seq_item req = uart_seq_item::type_id::create("req");
        start_item(req);
        req.data                = 8'h5A;
        req.direction            = HOST_TO_DUT;
        req.inject_bad_stop_bit = 1'b1; // malformed frame
        finish_item(req);
        `uvm_info("UART_ERROR_SEQ", "Sent byte with bad stop bit (framing error)", UVM_MEDIUM)
    endtask

endclass

`endif
