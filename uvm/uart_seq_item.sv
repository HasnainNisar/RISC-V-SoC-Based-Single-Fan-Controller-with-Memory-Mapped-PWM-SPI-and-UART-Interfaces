// =====================================================================
// uart_seq_item.sv - UART Transaction
//
// Represents one UART byte.
//   - direction = HOST_TO_DUT : driver sends this byte to the DUT's
//                 rx pin (simulates a terminal/host command, e.g.
//                 "load profile" or "set duty").
//   - direction = DUT_TO_HOST : populated by the monitor when it
//                 observes the DUT transmitting a byte (e.g. a status
//                 report).
//   - inject_bad_stop_bit : error-case control, used by the driver to
//                 send a malformed frame (framing error case).
// =====================================================================

`ifndef UART_SEQ_ITEM_SV
`define UART_SEQ_ITEM_SV

typedef enum { HOST_TO_DUT, DUT_TO_HOST } uart_dir_e;

class uart_seq_item extends uvm_sequence_item;

    rand bit [7:0]   data;
    rand uart_dir_e  direction;
    rand bit         inject_bad_stop_bit;

    bit frame_error_seen; // monitor sets this if a bad frame was observed

    `uvm_object_utils_begin(uart_seq_item)
        `uvm_field_int (data,                 UVM_ALL_ON)
        `uvm_field_enum(uart_dir_e, direction, UVM_ALL_ON)
        `uvm_field_int (inject_bad_stop_bit,  UVM_ALL_ON)
        `uvm_field_int (frame_error_seen,     UVM_ALL_ON | UVM_NOPACK)
    `uvm_object_utils_end

    function new(string name = "uart_seq_item");
        super.new(name);
    endfunction

endclass

`endif
