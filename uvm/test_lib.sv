// =====================================================================
// test_lib.sv - UVM Tests
//
//   base_test      : builds the env, wires up the virtual interface
//                     and UART timing to all agents. Not run directly.
//   normal_test     : runs SPI/UART normal sequences (profile load +
//                     host commands), letting the core's own program
//                     (test_program.hex) run concurrently.
//   error_test      : runs SPI "no response" and UART "bad frame"
//                     error sequences.
//   failsafe_test   : runs the stall -> recovery fail-safe sequence.
//   regression_test : runs normal, error, and failsafe scenarios
//                     back-to-back for a single full-regression run.
//   core_instr_test : runs instr_test.hex (all 37 RV32I instructions; start with
//                     +IMEM=instr_test.hex) and checks the DMEM signature against the
//                     independent golden model plus 100% instruction coverage.
// =====================================================================

`ifndef TEST_LIB_SV
`define TEST_LIB_SV

class base_test extends uvm_test;

    `uvm_component_utils(base_test)

    soc_env env;
    virtual soc_if vif;
    real uart_bit_period_ns = 320.0; // must match tb_top_uvm's DUT config

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif))
            `uvm_fatal("BASE_TEST", "Could not get vif from config_db")

        env = soc_env::type_id::create("env", this);

        // Propagate vif + UART timing to every agent component
        uvm_config_db#(virtual soc_if)::set(this, "env.*", "vif", vif);
        uvm_config_db#(real)::set(this, "env.uart_agt.*", "bit_period_ns", uart_bit_period_ns);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

endclass

// ---------------------------------------------------------------------
class normal_test extends base_test;

    `uvm_component_utils(normal_test)

    function new(string name = "normal_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_normal_seq  spi_seq;
        uart_normal_seq uart_seq;

        phase.raise_objection(this);
        `uvm_info("NORMAL_TEST", "Starting normal-operation test", UVM_LOW)

        spi_seq  = spi_normal_seq::type_id::create("spi_seq");
        uart_seq = uart_normal_seq::type_id::create("uart_seq");

        fork
            // SPI: the DUT's single transfer happens ~1 us after reset, so
            // the slave-side sequence must already be waiting at t=0.
            spi_seq.start(env.spi_agt.sequencer);
            // UART: host commands go in after the core program has settled.
            begin
                #20000;
                uart_seq.start(env.uart_agt.sequencer);
            end
        join

        // Let the fan spin all the way up (~30 PWM windows) so the scoreboard can check
        // that the RPM settles exactly at duty * MAX_RPM / 255.
        #180000;

        `uvm_info("NORMAL_TEST", "Normal-operation test complete", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass

// ---------------------------------------------------------------------
class error_test extends base_test;

    `uvm_component_utils(error_test)

    function new(string name = "error_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_error_seq   spi_err;
        uart_normal_seq uart_norm;
        uart_error_seq  uart_err;

        phase.raise_objection(this);
        `uvm_info("ERROR_TEST", "Starting error-case test", UVM_LOW)

        spi_err   = spi_error_seq::type_id::create("spi_err");
        uart_norm = uart_normal_seq::type_id::create("uart_norm");
        uart_err  = uart_error_seq::type_id::create("uart_err");

        // The core's UART receive path (rx_wait: in test_program.hex) polls in a
        // tight loop until it sees RX_VALID -- a bad-stop-bit frame never sets
        // RX_VALID (only frame_error), so if that were the ONLY byte ever sent
        // the core would spin in rx_wait forever and never reach the later
        // unmapped-access section that the scoreboard's end-of-test checks
        // (bus_error, DMEM[7]) depend on. So a well-formed byte is sent first
        // to let the core's program run to completion; the malformed frame is
        // sent afterward, once the core is no longer listening, purely to
        // exercise the UART receiver's frame_error detection in isolation.
        fork
            // SPI: unresponsive slave for the core's (single) transfer at ~1 us
            spi_err.start(env.spi_agt.sequencer);
            // UART: one well-formed byte so the core's rx_wait loop unblocks
            begin
                #20000;
                uart_norm.start(env.uart_agt.sequencer);
            end
        join

        #10000;

        // Now exercise the framing-error path (core is done and no longer polling)
        uart_err.start(env.uart_agt.sequencer);

        #10000;

        `uvm_info("ERROR_TEST", "Error-case test complete", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass

// ---------------------------------------------------------------------
class failsafe_test extends base_test;

    `uvm_component_utils(failsafe_test)

    function new(string name = "failsafe_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_normal_seq  spi_seq;
        uart_normal_seq uart_seq;
        failsafe_seq    fs_seq;

        phase.raise_objection(this);
        `uvm_info("FAILSAFE_TEST", "Starting fail-safe (stall/recovery) test", UVM_LOW)

        spi_seq  = spi_normal_seq::type_id::create("spi_seq");
        uart_seq = uart_normal_seq::type_id::create("uart_seq");
        fs_seq   = failsafe_seq::type_id::create("fs_seq");

        // This test's real interest is the PWM stall/fail-safe FSM, but the core still
        // runs the full test_program.hex alongside it (SPI profile load, then UART TX,
        // then it blocks in its UART rx_wait poll loop until a well-formed byte
        // arrives). Without servicing SPI/UART here the core would either read back
        // garbage (SPI has no cooperating slave) or -- worse -- spin in rx_wait
        // forever, so it would never reach the unmapped-access section the
        // scoreboard's end-of-test checks depend on. Service both normally, in
        // parallel with the fail-safe sequence (PWM is independent of both).
        fork
            spi_seq.start(env.spi_agt.sequencer);
            begin
                #20000;
                uart_seq.start(env.uart_agt.sequencer);
            end
            begin
                #5000;                 // give the core time to enable PWM first
                fs_seq.start(null);    // not tied to a sequencer; drives vif directly
            end
        join

        `uvm_info("FAILSAFE_TEST", "Fail-safe test complete", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass

// ---------------------------------------------------------------------
class regression_test extends base_test;

    `uvm_component_utils(regression_test)

    function new(string name = "regression_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_normal_seq  spi_norm;
        uart_normal_seq uart_norm;
        uart_error_seq  uart_err;
        failsafe_seq    fs_seq;

        phase.raise_objection(this);
        `uvm_info("REGRESSION_TEST", "Starting full regression", UVM_LOW)

        spi_norm  = spi_normal_seq::type_id::create("spi_norm");
        uart_norm = uart_normal_seq::type_id::create("uart_norm");
        fork
            spi_norm.start(env.spi_agt.sequencer);   // must be ready before the core's SPI transfer (~1 us)
            begin
                #20000;                               // let core program settle
                uart_norm.start(env.uart_agt.sequencer);
            end
        join

        #10000;

        // NOTE: spi_error_seq is covered by error_test only. test_program.hex
        // performs a single SPI transfer, which normal_seq already consumed.
        uart_err = uart_error_seq::type_id::create("uart_err");
        uart_err.start(env.uart_agt.sequencer);

        #10000;

        fs_seq = failsafe_seq::type_id::create("fs_seq");
        fs_seq.start(null);

        `uvm_info("REGRESSION_TEST", "Full regression complete", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass

// ---------------------------------------------------------------------
class core_instr_test extends base_test;

    `uvm_component_utils(core_instr_test)

    function new(string name = "core_instr_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        // This test runs a different program: turn off the system-program checks
        uvm_config_db#(bit)::set(this, "env.sb", "check_system_program", 1'b0);
        super.build_phase(phase);
    endfunction

    task run_phase(uvm_phase phase);
        bit [31:0] expected [0:255];
        int        n, errors;
        real       cov;

        phase.raise_objection(this);
        `uvm_info("CORE_TEST", "Starting RV32I core-instruction test", UVM_LOW)

        if (!$test$plusargs("IMEM"))
            `uvm_fatal("CORE_TEST", "Run this test with +IMEM=instr_test.hex (see run_uvm.do)")

        // ~300 single-cycle instructions; generous margin for the halt loop
        repeat (3000) @(posedge vif.clk);

        // ---- compare DMEM signature with the golden ISS results ----
        $readmemh("instr_expected.hex", expected);
        n      = expected[0];
        errors = 0;
        for (int i = 0; i < n; i++) begin
            if (vif.dmem_tap[i] !== expected[i+1]) begin
                errors++;
                `uvm_error("CORE_TEST",
                    $sformatf("DMEM[%0d]=0x%08h expected 0x%08h", i, vif.dmem_tap[i], expected[i+1]))
            end
        end
        `uvm_info("CORE_TEST",
            $sformatf("%0d of %0d result words match the golden model", n - errors, n), UVM_LOW)

        // ---- every RV32I instruction / variant must have been executed ----
        cov = env.sb.core_cg.get_coverage();
        `uvm_info("CORE_TEST", $sformatf("Instruction coverage = %0.1f%%", cov), UVM_LOW)
        if (cov < 100.0)
            `uvm_error("CORE_TEST", $sformatf("Instruction coverage %0.1f%% < 100%%", cov))

        phase.drop_objection(this);
    endtask

endclass

`endif
