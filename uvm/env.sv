// =====================================================================
// env.sv - UVM Environment
// =====================================================================

`ifndef SOC_ENV_SV
`define SOC_ENV_SV

class soc_env extends uvm_env;

    `uvm_component_utils(soc_env)

    spi_agent  spi_agt;
    uart_agent uart_agt;
    pwm_agent  pwm_agt;
    core_monitor core_mon;
    scoreboard sb;

    function new(string name = "soc_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        spi_agt  = spi_agent::type_id::create("spi_agt", this);
        uart_agt = uart_agent::type_id::create("uart_agt", this);
        pwm_agt  = pwm_agent::type_id::create("pwm_agt", this);
        core_mon = core_monitor::type_id::create("core_mon", this);
        sb       = scoreboard::type_id::create("sb", this);

        // Both agents active by default: SPI agent drives the slave
        // side, UART agent can drive host->DUT bytes. Tests may
        // override to UVM_PASSIVE via config_db if only observation
        // is needed.
        uvm_config_db#(uvm_active_passive_enum)::set(this, "spi_agt", "is_active", UVM_ACTIVE);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "uart_agt", "is_active", UVM_ACTIVE);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        spi_agt.monitor.ap.connect(sb.spi_imp);
        uart_agt.monitor.ap.connect(sb.uart_imp);
        pwm_agt.monitor.ap.connect(sb.pwm_imp);
        core_mon.ap.connect(sb.core_imp);

        // Drivers publish what they were asked to do, so the scoreboard can check the DUT's view
        if (spi_agt.get_is_active() == UVM_ACTIVE)
            spi_agt.driver.exp_ap.connect(sb.spi_exp_imp);
        if (uart_agt.get_is_active() == UVM_ACTIVE)
            uart_agt.driver.exp_ap.connect(sb.uart_exp_imp);
    endfunction

endclass

`endif
