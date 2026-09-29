// =====================================================================
// core_monitor.sv - Core instruction-stream monitor (passive)
//
// Observes the instruction the core executes each clock (PC + instruction
// word via soc_if taps) and publishes it to the scoreboard, which samples
// the instruction-level functional coverage (all RV32I opcodes / funct3 /
// funct7 variants) and counts executed instructions.
// =====================================================================

`ifndef CORE_MONITOR_SV
`define CORE_MONITOR_SV

class core_item extends uvm_object;

    bit [31:0] pc;
    bit [31:0] instr;

    `uvm_object_utils(core_item)

    function new(string name = "core_item");
        super.new(name);
    endfunction

endclass

class core_monitor extends uvm_monitor;

    `uvm_component_utils(core_monitor)

    virtual soc_if vif;
    uvm_analysis_port #(core_item) ap;

    function new(string name = "core_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif))
            `uvm_fatal("CORE_MON", "Virtual interface not set for core_monitor")
    endfunction

    task run_phase(uvm_phase phase);
        bit [31:0] last_pc = 32'hFFFF_FFFF;

        forever begin
            @(posedge vif.clk);
            // Skip reset, and skip repeats of the same PC (the program's halt loop)
            if (vif.rst_n === 1'b1 && vif.core_pc !== last_pc && ^vif.core_instr !== 1'bx) begin
                core_item item = core_item::type_id::create("core_item");
                item.pc    = vif.core_pc;
                item.instr = vif.core_instr;
                last_pc    = vif.core_pc;
                ap.write(item);
            end
        end
    endtask

endclass

`endif
