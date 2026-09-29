// =====================================================================
// pwm_agent.sv - PWM Agent (always passive: monitor only)
// =====================================================================

`ifndef PWM_AGENT_SV
`define PWM_AGENT_SV

class pwm_agent extends uvm_agent;

    `uvm_component_utils(pwm_agent)

    pwm_monitor monitor;

    function new(string name = "pwm_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = pwm_monitor::type_id::create("monitor", this);
    endfunction

endclass

`endif
