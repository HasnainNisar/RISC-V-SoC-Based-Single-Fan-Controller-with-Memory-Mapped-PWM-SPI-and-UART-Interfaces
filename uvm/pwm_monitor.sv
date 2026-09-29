// =====================================================================
// pwm_monitor.sv - PWM / Fan Monitor (passive, no driver)
//
// PWM is a purely output-side peripheral in this system (the core
// configures it via registers; there is nothing external to "drive"
// on the PWM side). This monitor samples pwm_out_debug / fan_rpm_debug
// once per PWM window and reports measured duty %, RPM, and DUT
// internal en/fault/duty-register taps (see soc_if.sv) for the
// scoreboard's stall/fail-safe checks.
// =====================================================================

`ifndef PWM_MONITOR_SV
`define PWM_MONITOR_SV

class pwm_sample extends uvm_object;

    bit [7:0]  measured_duty;   // 0-255, measured from pwm_out_debug
    bit [15:0] rpm;
    bit        en;
    bit        fault;
    bit        failsafe;        // drive removed by the fail-safe FSM
    bit [7:0]  duty_reg;        // DUT's PWM_DUTY register value (expected)

    `uvm_object_utils_begin(pwm_sample)
        `uvm_field_int(measured_duty, UVM_ALL_ON)
        `uvm_field_int(rpm,           UVM_ALL_ON)
        `uvm_field_int(en,            UVM_ALL_ON)
        `uvm_field_int(fault,         UVM_ALL_ON)
        `uvm_field_int(failsafe,      UVM_ALL_ON)
        `uvm_field_int(duty_reg,      UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "pwm_sample");
        super.new(name);
    endfunction

endclass

class pwm_monitor extends uvm_monitor;

    `uvm_component_utils(pwm_monitor)

    virtual soc_if vif;
    uvm_analysis_port #(pwm_sample) ap;

    // Window length must match pwm_controller's 8-bit free-running
    // counter (256 clk cycles per period).
    localparam int WINDOW_CYCLES = 256;

    function new(string name = "pwm_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif))
            `uvm_fatal("PWM_MON", "Virtual interface not set for pwm_monitor")
    endfunction

    task run_phase(uvm_phase phase);
        int high_count;

        forever begin
            high_count = 0;
            for (int i = 0; i < WINDOW_CYCLES; i++) begin
                @(posedge vif.clk);
                if (vif.pwm_out_debug)
                    high_count++;
            end

            begin
                pwm_sample s = pwm_sample::type_id::create("pwm_sample_item");
                s.measured_duty = high_count[7:0];
                s.rpm           = vif.fan_rpm_debug;
                s.en            = vif.pwm_en_tap;
                s.fault         = vif.pwm_fault_tap;
                s.failsafe      = vif.pwm_failsafe_tap;
                s.duty_reg      = vif.pwm_duty_tap;

                `uvm_info("PWM_MON",
                    $sformatf("Window sample: duty=%0d/255 rpm=%0d en=%0b fault=%0b",
                              s.measured_duty, s.rpm, s.en, s.fault),
                    UVM_HIGH)

                ap.write(s);
            end
        end
    endtask

endclass

`endif
