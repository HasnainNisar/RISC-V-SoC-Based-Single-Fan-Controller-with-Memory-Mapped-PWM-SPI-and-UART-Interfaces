// =====================================================================
// scoreboard.sv - Scoreboard, checkers and functional coverage
//
// Streams handled (analysis ports):
//   spi_imp / spi_exp_imp : observed SPI transfers (monitor) vs the slave
//                           responses the driver was asked to give
//   uart_imp / uart_exp_imp: DUT TX bytes (monitor) / host->DUT bytes (driver)
//   pwm_imp               : per-window PWM duty / RPM / fault / fail-safe samples
//   core_imp              : executed instruction stream (instruction coverage)
//
// Checks performed
//   SPI   : MOSI byte == what the core sends (0xA5); MISO seen by the DUT ==
//           the response the driver gave (0 if none/unserved)
//   PROFILE LOADING (end of test): the bytes received over SPI were stored by
//           the core into DMEM[1..4] AND into config SRAM[0..3]
//   UART  : DUT TX byte == 'A'; first good host byte reached the core
//           (DMEM[6]); a bad-stop-bit frame raised frame_error in the DUT
//   PWM   : measured duty == programmed duty; RPM never overshoots the target,
//           never ramps faster than the fan's inertia, and settles exactly at
//           duty*MAX_RPM/255
//   MEMORY: SRAM write/read, config-SRAM preload read, unmapped-access
//           behaviour (bus_error + 0xDEADBEEF)
//   SVA   : no assertion failed in soc_assertions
//
// Functional coverage: spi_cg, uart_cg, pwm_cg (duty x fault x fail-safe x RPM),
// core_cg (every RV32I instruction / funct3 / funct7 variant).
// Code coverage (line/branch/condition/FSM/toggle) is collected by the
// simulator -- see run_uvm.do / run_cov.do.
// =====================================================================

`ifndef SCOREBOARD_SV
`define SCOREBOARD_SV

`uvm_analysis_imp_decl(_spi)
`uvm_analysis_imp_decl(_spi_exp)
`uvm_analysis_imp_decl(_uart)
`uvm_analysis_imp_decl(_uart_exp)
`uvm_analysis_imp_decl(_pwm)
`uvm_analysis_imp_decl(_core)

class scoreboard extends uvm_scoreboard;

    `uvm_component_utils(scoreboard)

    uvm_analysis_imp_spi      #(spi_seq_item,  scoreboard) spi_imp;
    uvm_analysis_imp_spi_exp  #(spi_seq_item,  scoreboard) spi_exp_imp;
    uvm_analysis_imp_uart     #(uart_seq_item, scoreboard) uart_imp;
    uvm_analysis_imp_uart_exp #(uart_seq_item, scoreboard) uart_exp_imp;
    uvm_analysis_imp_pwm      #(pwm_sample,    scoreboard) pwm_imp;
    uvm_analysis_imp_core     #(core_item,     scoreboard) core_imp;

    virtual soc_if vif;

    // ---- configuration (set via config_db) ----
    bit          check_system_program = 1'b1;  // 0 for core_instr_test (different program)
    bit [7:0]    exp_spi_mosi_byte    = 8'hA5; // what test_program.hex sends on MOSI
    bit [7:0]    exp_uart_tx_byte     = 8'h41; // 'A'
    int unsigned exp_spi_transfers    = 4;     // profile-loading transfers in test_program.hex
    int unsigned rpm_max              = 3000;  // fan_model MAX_RPM
    int unsigned rpm_ramp_step        = 50;    // fan_model RAMP_STEP

    // ---- statistics ----
    int spi_transfers_seen;
    int uart_bytes_seen;
    int uart_frame_errors_seen;
    int pwm_fault_events_seen;
    int pwm_failsafe_events_seen;
    int core_instr_seen;

    // ---- bookkeeping ----
    spi_seq_item  spi_exp_q[$];      // responses the driver was asked to give (FIFO)
    bit [7:0]     spi_rx_hist[$];    // byte the DUT should have received, per transfer
    uart_seq_item uart_exp_q[$];     // host->DUT items that were sent
    pwm_sample    last_pwm_sample;

    // -------------------------------------------------------------
    // Functional coverage
    // -------------------------------------------------------------
    covergroup spi_cg with function sample(bit [7:0] mosi_byte, bit no_resp);
        option.per_instance = 1;
        cp_mosi_byte: coverpoint mosi_byte {
            bins low_byte  = {[8'h00:8'h3F]};
            bins mid_byte  = {[8'h40:8'hBF]};
            bins high_byte = {[8'hC0:8'hFF]};
        }
        cp_no_resp: coverpoint no_resp;
    endgroup

    covergroup uart_cg with function sample(bit [7:0] data, bit frame_err);
        option.per_instance = 1;
        cp_data: coverpoint data {
            bins printable    = {[8'h20:8'h7E]};
            bins control_low  = {[8'h00:8'h1F]};
            bins high_byte    = {[8'h80:8'hFF]};
        }
        cp_frame_err: coverpoint frame_err;
    endgroup

    covergroup pwm_cg with function sample(bit [7:0] duty, bit fault, bit en, bit failsafe, bit [15:0] rpm);
        option.per_instance = 1;
        cp_duty: coverpoint duty {
            bins zero        = {0};
            bins low         = {[1:63]};
            bins mid         = {[64:191]};
            bins high        = {[192:254]};
            bins full        = {255};
        }
        cp_fault:    coverpoint fault;
        cp_en:       coverpoint en;
        cp_failsafe: coverpoint failsafe;
        cp_rpm: coverpoint rpm {
            bins stopped = {0};
            bins ramping = {[1:1499]};
            bins cruise  = {[1500:3000]};
        }
        cross cp_duty, cp_fault;
        cross cp_fault, cp_failsafe;
    endgroup

    // Instruction coverage: every RV32I instruction (and variant) must be executed
    covergroup core_cg with function sample(bit [31:0] instr);
        option.per_instance = 1;
        cp_opcode: coverpoint instr[6:0] {
            bins lui    = {7'h37};
            bins auipc  = {7'h17};
            bins jal    = {7'h6F};
            bins jalr   = {7'h67};
            bins branch = {7'h63};
            bins load   = {7'h03};
            bins store  = {7'h23};
            bins op_imm = {7'h13};
            bins op     = {7'h33};
            bins fence  = {7'h0F};
        }
        cp_branch: coverpoint instr[14:12] iff (instr[6:0] == 7'h63) {
            bins beq = {3'b000}; bins bne = {3'b001}; bins blt = {3'b100};
            bins bge = {3'b101}; bins bltu = {3'b110}; bins bgeu = {3'b111};
        }
        cp_load: coverpoint instr[14:12] iff (instr[6:0] == 7'h03) {
            bins lb = {3'b000}; bins lh = {3'b001}; bins lw = {3'b010};
            bins lbu = {3'b100}; bins lhu = {3'b101};
        }
        cp_store: coverpoint instr[14:12] iff (instr[6:0] == 7'h23) {
            bins sb = {3'b000}; bins sh = {3'b001}; bins sw = {3'b010};
        }
        cp_op_imm: coverpoint {instr[30] & (instr[14:12] == 3'b101), instr[14:12]} iff (instr[6:0] == 7'h13) {
            bins addi = {4'b0000}; bins slti = {4'b0010}; bins sltiu = {4'b0011};
            bins xori = {4'b0100}; bins ori  = {4'b0110}; bins andi  = {4'b0111};
            bins slli = {4'b0001}; bins srli = {4'b0101}; bins srai  = {4'b1101};
        }
        cp_op: coverpoint {instr[30], instr[14:12]} iff (instr[6:0] == 7'h33) {
            bins add = {4'b0000}; bins sub = {4'b1000}; bins sll = {4'b0001};
            bins slt = {4'b0010}; bins sltu = {4'b0011}; bins xor_ = {4'b0100};
            bins srl = {4'b0101}; bins sra = {4'b1101}; bins or_  = {4'b0110};
            bins and_ = {4'b0111};
        }
    endgroup

    function new(string name = "scoreboard", uvm_component parent = null);
        super.new(name, parent);
        spi_imp      = new("spi_imp", this);
        spi_exp_imp  = new("spi_exp_imp", this);
        uart_imp     = new("uart_imp", this);
        uart_exp_imp = new("uart_exp_imp", this);
        pwm_imp      = new("pwm_imp", this);
        core_imp     = new("core_imp", this);
        spi_cg  = new();
        uart_cg = new();
        pwm_cg  = new();
        core_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif))
            `uvm_fatal("SCOREBOARD", "Virtual interface not set for scoreboard")
        void'(uvm_config_db#(bit)::get(this, "", "check_system_program", check_system_program));
    endfunction

    // -------------------------------------------------------------
    // SPI: expected response (from driver) and observed transfer (from monitor)
    // -------------------------------------------------------------
    function void write_spi_exp(spi_seq_item t);
        spi_seq_item c = spi_seq_item::type_id::create("spi_exp_copy");
        c.resp_byte          = t.resp_byte;
        c.inject_no_response = t.inject_no_response;
        spi_exp_q.push_back(c);
    endfunction

    function void write_spi(spi_seq_item t);
        bit [7:0] exp_miso = 8'h00; // unserved / no-response transfers read back 0x00

        spi_transfers_seen++;
        if (spi_exp_q.size() > 0) begin
            spi_seq_item e = spi_exp_q.pop_front();
            exp_miso = e.inject_no_response ? 8'h00 : e.resp_byte;
        end
        spi_rx_hist.push_back(exp_miso);

        spi_cg.sample(t.mosi_byte, (exp_miso == 8'h00));

        if (check_system_program && t.mosi_byte !== exp_spi_mosi_byte)
            `uvm_error("SCOREBOARD",
                $sformatf("SPI MOSI mismatch (transfer #%0d): DUT sent 0x%0h, expected 0x%0h",
                          spi_transfers_seen, t.mosi_byte, exp_spi_mosi_byte))
        if (t.miso_byte !== exp_miso)
            `uvm_error("SCOREBOARD",
                $sformatf("SPI MISO mismatch (transfer #%0d): line carried 0x%0h, expected 0x%0h",
                          spi_transfers_seen, t.miso_byte, exp_miso))

        `uvm_info("SCOREBOARD",
            $sformatf("SPI transfer #%0d: mosi=0x%0h miso=0x%0h (expected miso 0x%0h)",
                      spi_transfers_seen, t.mosi_byte, t.miso_byte, exp_miso),
            UVM_MEDIUM)
    endfunction

    // -------------------------------------------------------------
    // UART: host->DUT (driver) and DUT->host (monitor)
    // -------------------------------------------------------------
    function void write_uart_exp(uart_seq_item t);
        uart_seq_item c = uart_seq_item::type_id::create("uart_exp_copy");
        c.data                = t.data;
        c.inject_bad_stop_bit = t.inject_bad_stop_bit;
        uart_exp_q.push_back(c);
    endfunction

    function void write_uart(uart_seq_item t);
        uart_bytes_seen++;
        if (t.frame_error_seen)
            uart_frame_errors_seen++;

        uart_cg.sample(t.data, t.frame_error_seen);

        if (check_system_program && t.direction == DUT_TO_HOST) begin
            if (t.frame_error_seen)
                `uvm_error("SCOREBOARD", "DUT transmitted a frame with a bad stop bit")
            else if (t.data !== exp_uart_tx_byte)
                `uvm_error("SCOREBOARD",
                    $sformatf("UART TX byte mismatch: got 0x%0h, expected 0x%0h", t.data, exp_uart_tx_byte))
        end

        `uvm_info("SCOREBOARD",
            $sformatf("UART byte #%0d: dir=%s data=0x%0h frame_err=%0b",
                      uart_bytes_seen, t.direction.name(), t.data, t.frame_error_seen),
            UVM_MEDIUM)
    endfunction

    // -------------------------------------------------------------
    // PWM / fan sample checks (once per PWM window)
    // -------------------------------------------------------------
    function void write_pwm(pwm_sample s);
        bit          prev_ok;
        int unsigned target;
        int          diff;

        // Compare only when PWM has been enabled, un-faulted and unchanged for a FULL
        // previous window; the first window after enable / a duty change / a fault is partial.
        prev_ok = (last_pwm_sample != null) && last_pwm_sample.en && !last_pwm_sample.fault &&
                  !last_pwm_sample.failsafe && (last_pwm_sample.duty_reg == s.duty_reg);

        if (s.fault    && (last_pwm_sample == null || !last_pwm_sample.fault))    pwm_fault_events_seen++;
        if (s.failsafe && (last_pwm_sample == null || !last_pwm_sample.failsafe)) pwm_failsafe_events_seen++;

        pwm_cg.sample(s.measured_duty, s.fault, s.en, s.failsafe, s.rpm);

        if (s.en && !s.fault && !s.failsafe && prev_ok) begin
            // (1) duty measured on pwm_out must equal the programmed duty register
            diff = (s.measured_duty > s.duty_reg) ? (s.measured_duty - s.duty_reg)
                                                  : (s.duty_reg - s.measured_duty);
            if (diff > 2)
                `uvm_error("SCOREBOARD",
                    $sformatf("PWM duty mismatch: measured=%0d programmed=%0d", s.measured_duty, s.duty_reg))

            // (2) RPM measurement: bounded by target, limited by inertia, settles exactly at target
            target = (s.duty_reg * rpm_max) / 255;
            if (s.rpm > target + rpm_ramp_step)
                `uvm_error("SCOREBOARD",
                    $sformatf("RPM overshoot: rpm=%0d target=%0d", s.rpm, target))
            if (s.rpm > last_pwm_sample.rpm && (s.rpm - last_pwm_sample.rpm) > rpm_ramp_step)
                `uvm_error("SCOREBOARD",
                    $sformatf("RPM rose too fast: %0d -> %0d (max step %0d)", last_pwm_sample.rpm, s.rpm, rpm_ramp_step))
            if (s.rpm != 0 && s.rpm == last_pwm_sample.rpm && s.rpm != target)
                `uvm_error("SCOREBOARD",
                    $sformatf("RPM settled at wrong value: rpm=%0d target=%0d", s.rpm, target))
        end

        last_pwm_sample = s;
    endfunction

    // -------------------------------------------------------------
    // Core instruction stream -> instruction coverage
    // -------------------------------------------------------------
    function void write_core(core_item t);
        core_instr_seen++;
        core_cg.sample(t.instr);
    endfunction

    // -------------------------------------------------------------
    // End-of-test checks (memory contents / side effects inside the DUT)
    // -------------------------------------------------------------
    function void check_phase(uvm_phase phase);
        bit          got_good = 1'b0, got_bad = 1'b0;
        bit [7:0]    first_good = 8'h00;

        super.check_phase(phase);

        if (vif.sva_fail_count != 0)
            `uvm_error("SVA", $sformatf("%0d SystemVerilog assertion failure(s) in soc_assertions", vif.sva_fail_count))

        if (!check_system_program) return;

        // ---- SRAM / config SRAM / bus ----
        if (vif.dmem_tap[0] !== 32'd123)
            `uvm_error("MEM", $sformatf("DMEM[0]=0x%0h, expected 123 (SRAM write/read by the core)", vif.dmem_tap[0]))
        if (vif.dmem_tap[5] !== 32'hCAFE_DA7A)
            `uvm_error("MEM", $sformatf("DMEM[5]=0x%0h, expected 0xCAFEDA7A (core read of config SRAM PROFILE_ID)", vif.dmem_tap[5]))
        if (vif.cfg_tap[4] !== 32'hCAFE_DA7A)
            `uvm_error("MEM", $sformatf("CFG[4]=0x%0h, expected preloaded 0xCAFEDA7A", vif.cfg_tap[4]))
        if (vif.dmem_tap[7] !== 32'hDEAD_BEEF)
            `uvm_error("BUS", $sformatf("DMEM[7]=0x%0h, unmapped read should return 0xDEADBEEF", vif.dmem_tap[7]))
        if (!vif.bus_error_seen)
            `uvm_error("BUS", "bus_error never asserted for the program's unmapped access")

        // ---- PROFILE LOADING: SPI bytes must have been stored to DMEM and to config SRAM ----
        if (spi_transfers_seen != exp_spi_transfers)
            `uvm_error("PROFILE_LOAD",
                $sformatf("saw %0d SPI transfers, expected %0d", spi_transfers_seen, exp_spi_transfers))
        for (int i = 0; i < 4 && i < spi_rx_hist.size(); i++) begin
            if (vif.dmem_tap[1+i] !== {24'd0, spi_rx_hist[i]})
                `uvm_error("PROFILE_LOAD",
                    $sformatf("DMEM[%0d]=0x%0h, expected SPI byte 0x%0h", 1+i, vif.dmem_tap[1+i], spi_rx_hist[i]))
            if (vif.cfg_tap[i] !== {24'd0, spi_rx_hist[i]})
                `uvm_error("PROFILE_LOAD",
                    $sformatf("CFG[%0d]=0x%0h, expected profile byte 0x%0h loaded via SPI", i, vif.cfg_tap[i], spi_rx_hist[i]))
        end

        // ---- UART receive path ----
        foreach (uart_exp_q[i]) begin
            if (uart_exp_q[i].inject_bad_stop_bit) got_bad = 1'b1;
            else if (!got_good) begin got_good = 1'b1; first_good = uart_exp_q[i].data; end
        end
        if (got_good && vif.dmem_tap[6] !== {24'd0, first_good})
            `uvm_error("UART_RX",
                $sformatf("core received 0x%0h (DMEM[6]), first good host byte was 0x%0h", vif.dmem_tap[6], first_good))
        if (got_bad && !vif.uart_frame_err_seen)
            `uvm_error("UART_RX", "host sent a bad-stop-bit frame but the DUT never flagged frame_error")
        if (!got_bad && vif.uart_frame_err_seen)
            `uvm_error("UART_RX", "DUT flagged frame_error although every host frame was well-formed")
        if (got_good && !vif.uart_rx_valid_seen)
            `uvm_error("UART_RX", "host sent a good frame but the DUT never produced rx_valid")
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCOREBOARD",
            $sformatf("\n==== SCOREBOARD SUMMARY ====\n  SPI transfers      : %0d\n  UART bytes (DUT tx): %0d\n  UART frame errs    : %0d\n  PWM fault events   : %0d\n  PWM fail-safe evts : %0d\n  Instructions seen  : %0d\n  SPI coverage       : %0.1f%%\n  UART coverage      : %0.1f%%\n  PWM coverage       : %0.1f%%\n  Instruction cov    : %0.1f%%\n=============================",
                      spi_transfers_seen, uart_bytes_seen, uart_frame_errors_seen,
                      pwm_fault_events_seen, pwm_failsafe_events_seen, core_instr_seen,
                      spi_cg.get_coverage(), uart_cg.get_coverage(),
                      pwm_cg.get_coverage(), core_cg.get_coverage()),
            UVM_LOW)
    endfunction

endclass

`endif
