// =====================================================================
// spi_seq_item.sv - SPI Transaction
//
// Represents one 8-bit SPI transfer as observed/driven at the pins.
// The DUT (spi_master) is always the SPI master in this system, so:
//   - resp_byte   : byte the agent (acting as slave) should drive on
//                   MISO for the next transfer (driver input).
//   - mosi_byte   : byte captured from MOSI during the transfer
//                   (monitor output).
//   - miso_byte   : byte captured from MISO during the transfer
//                   (monitor output, should equal resp_byte if the
//                   driver is working correctly).
//   - inject_no_response : error-case control -- if set, the driver
//                   deliberately does NOT respond on MISO (stuck-high
//                   / disconnected slave), to exercise the DUT's
//                   error handling.
// =====================================================================

`ifndef SPI_SEQ_ITEM_SV
`define SPI_SEQ_ITEM_SV

class spi_seq_item extends uvm_sequence_item;

    rand bit [7:0] resp_byte;
    rand bit       inject_no_response;

    bit [7:0] mosi_byte;
    bit [7:0] miso_byte;

    `uvm_object_utils_begin(spi_seq_item)
        `uvm_field_int(resp_byte,           UVM_ALL_ON)
        `uvm_field_int(inject_no_response,  UVM_ALL_ON)
        `uvm_field_int(mosi_byte,           UVM_ALL_ON | UVM_NOPACK)
        `uvm_field_int(miso_byte,           UVM_ALL_ON | UVM_NOPACK)
    `uvm_object_utils_end

    function new(string name = "spi_seq_item");
        super.new(name);
    endfunction

endclass

`endif
