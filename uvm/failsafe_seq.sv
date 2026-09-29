// =====================================================================
// failsafe_seq.sv - Stall detection + fail-safe behaviour sequence
//
// Full flow verified:
//   1. Fan stalls (jammed)      -> FAULT asserts after STALL_CYCLES.
//   2. Fail-safe engages        -> the PWM drive is REMOVED (pwm_out low)
//                                  for as long as the fail-safe is active.
//   3. Stall released           -> the controller re-applies drive, sees the
//                                  fan spin again and clears FAULT by itself
//                                  (no permanently latched broken state).
// =====================================================================

`ifndef FAILSAFE_SEQ_SV
`define FAILSAFE_SEQ_SV

class failsafe_seq extends uvm_sequence #(uvm_sequence_item);

    `uvm_object_utils(failsafe_seq)

    virtual soc_if vif;
    int stall_cycles    = 1200; // > STALL_CYCLES threshold (1024) + time to observe the fail-safe
    int recovery_cycles = 2500; // RETRY window + fan spin-up (a few PWM windows)

    function new(string name = "failsafe_seq");
        super.new(name);
    endfunction

    task body();
        bit fault_seen_during_stall;
        bit failsafe_seen;
        bit drive_while_failsafe;
        bit fault_cleared_after_recovery;
        int recovery_clks;

        if (!uvm_config_db#(virtual soc_if)::get(null, "*", "vif", vif))
            `uvm_fatal("FAILSAFE_SEQ", "Could not get vif from config_db")

        // ---- Step 1: inject stall ----
        `uvm_info("FAILSAFE_SEQ", "Step 1: injecting fan stall", UVM_MEDIUM)
        vif.fan_stall_inject <= 1'b1;

        fault_seen_during_stall = 1'b0;
        failsafe_seen           = 1'b0;
        drive_while_failsafe    = 1'b0;
        repeat (stall_cycles) begin
            @(posedge vif.clk);
            if (vif.pwm_fault_tap)    fault_seen_during_stall = 1'b1;
            if (vif.pwm_failsafe_tap) begin
                failsafe_seen = 1'b1;
                if (vif.pwm_out_debug) drive_while_failsafe = 1'b1;
            end
        end

        if (fault_seen_during_stall)
            `uvm_info("FAILSAFE_SEQ", "PASS: FAULT asserted during stall", UVM_LOW)
        else
            `uvm_error("FAILSAFE_SEQ", "FAIL: FAULT never asserted during stall")

        if (failsafe_seen)
            `uvm_info("FAILSAFE_SEQ", "PASS: fail-safe engaged (drive removed)", UVM_LOW)
        else
            `uvm_error("FAILSAFE_SEQ", "FAIL: fail-safe never engaged after the stall fault")

        if (drive_while_failsafe)
            `uvm_error("FAILSAFE_SEQ", "FAIL: PWM output was driven while the fail-safe was active")

        // ---- Step 2: release stall, allow automatic recovery ----
        `uvm_info("FAILSAFE_SEQ", "Step 2: releasing stall, checking recovery", UVM_MEDIUM)
        vif.fan_stall_inject <= 1'b0;

        fault_cleared_after_recovery = 1'b0;
        recovery_clks = 0;
        repeat (recovery_cycles) begin
            @(posedge vif.clk);
            if (!fault_cleared_after_recovery) begin
                recovery_clks++;
                if (!vif.pwm_fault_tap && !vif.pwm_failsafe_tap)
                    fault_cleared_after_recovery = 1'b1;
            end
            if (vif.pwm_failsafe_tap && vif.pwm_out_debug)
                `uvm_error("FAILSAFE_SEQ", "FAIL: PWM output driven while the fail-safe was active (recovery phase)")
        end

        if (fault_cleared_after_recovery)
            `uvm_info("FAILSAFE_SEQ",
                $sformatf("PASS: FAULT cleared automatically %0d clocks after the fan recovered", recovery_clks), UVM_LOW)
        else
            `uvm_error("FAILSAFE_SEQ", "FAIL: FAULT did not clear after fan recovery")
    endtask

endclass

`endif
