// =====================================================================
// tb_soc_top.sv - Directed Self-Checking Testbench
//
//   PART A - Full-SoC, program-driven tests (test_program.hex on the real
//            core through soc_top):
//              reset state, config-SRAM preload + read, SRAM r/w, PWM
//              setup, SPI profile loading (4 transfers -> DMEM + config
//              SRAM), UART transmit AND receive, unmapped-address access
//              (bus_error + 0xDEADBEEF).
//   PART B - Directed unit-level error/corner cases on the RTL blocks:
//              PWM stall -> FAULT -> fail-safe (drive removed) -> recovery,
//              duty=0 is not a stall, SPI start-while-busy, UART framing
//              error, UART good-frame receive.
//   PART C - Reset in the middle of operation.
//
// The core-instruction test lives in tb_core_instr.sv.
// Self-checking: pass/fail counters and a final summary. SVA assertions
// (soc_assertions.sv) run alongside and their failures are counted too.
// =====================================================================

`timescale 1ns/1ps

module tb_soc_top;

    // -----------------------------------------------------------------
    // Clock / Reset
    // -----------------------------------------------------------------
    localparam real CLK_PERIOD_NS = 20.0; // 50 MHz
    localparam int  UART_CLKS_PER_BIT = 16; // kept small for fast sim
    localparam real UART_BIT_NS = UART_CLKS_PER_BIT * CLK_PERIOD_NS;

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD_NS/2.0) clk = ~clk;

    // -----------------------------------------------------------------
    // Self-checking bookkeeping
    // -----------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task automatic check_equal(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual === expected) begin
            pass_count++;
            $display("[PASS] %-52s actual=0x%08h expected=0x%08h", name, actual, expected);
        end else begin
            fail_count++;
            $display("[FAIL] %-52s actual=0x%08h expected=0x%08h", name, actual, expected);
        end
    endtask

    task automatic check_true(string name, logic cond);
        if (cond) begin
            pass_count++;
            $display("[PASS] %-52s", name);
        end else begin
            fail_count++;
            $display("[FAIL] %-52s", name);
        end
    endtask

    // ===================================================================
    // DUT + external models
    // ===================================================================
    logic spi_sclk, spi_mosi, spi_miso, spi_cs_n;
    logic uart_tx_line, uart_rx_line;
    logic        pwm_out;
    logic [15:0] fan_rpm;
    logic        fan_stall_inject = 1'b0;
    logic        bus_error;

    soc_top #(
        .IMEM_INIT_FILE    ("test_program.hex"),
        .CFG_INIT_FILE     ("config_data.hex"),
        .UART_CLKS_PER_BIT (UART_CLKS_PER_BIT)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .spi_sclk     (spi_sclk),
        .spi_mosi     (spi_mosi),
        .spi_miso     (spi_miso),
        .spi_cs_n     (spi_cs_n),
        .uart_tx_line (uart_tx_line),
        .uart_rx_line (uart_rx_line),
        .pwm_out      (pwm_out),
        .fan_rpm_in   (fan_rpm),
        .bus_error    (bus_error)
    );

    // Virtual fan: PWM in -> RPM out (testbench-side model)
    fan_model #(.MAX_RPM(3000), .RAMP_STEP(50)) u_fan_model (
        .clk          (clk),
        .rst_n        (rst_n),
        .pwm_in       (pwm_out),
        .stall_inject (fan_stall_inject),
        .rpm_out      (fan_rpm)
    );

    // External SPI slave model (fake "smart fan module")
    logic [7:0] profile_bytes [0:7];
    logic [7:0] spi_rx_log    [0:7];
    int         spi_transfer_count;

    initial begin
        profile_bytes[0] = 8'hDE; profile_bytes[1] = 8'hAD;
        profile_bytes[2] = 8'hBE; profile_bytes[3] = 8'hEF;
        profile_bytes[4] = 8'h11; profile_bytes[5] = 8'h22;
        profile_bytes[6] = 8'h33; profile_bytes[7] = 8'h44;
    end

    spi_slave_model #(.NUM_PROFILE_BYTES (8)) u_spi_slave (
        .sclk           (spi_sclk),
        .cs_n           (spi_cs_n),
        .mosi           (spi_mosi),
        .miso           (spi_miso),
        .profile_bytes  (profile_bytes),
        .rx_log         (spi_rx_log),
        .transfer_count (spi_transfer_count)
    );

    // External UART terminal model
    uart_terminal_model #(.BIT_PERIOD_NS (UART_BIT_NS)) u_uart_terminal (
        .term_tx_line (uart_rx_line), // terminal's TX drives DUT's rx
        .term_rx_line (uart_tx_line)  // terminal's RX watches DUT's tx
    );

    // Assertions on the full SoC
    soc_assertions #(.STALL_CYCLES(1024), .RETRY_CYCLES(256)) u_sva (
        .clk(clk), .rst_n(rst_n),
        .pc            (u_dut.u_core.pc),
        .core_re       (u_dut.core_dre),
        .core_we       (u_dut.core_dwe),
        .core_rdata    (u_dut.core_drdata),
        .bus_error     (bus_error),
        .dmem_sel      (u_dut.dmem_sel),
        .cfg_sel       (u_dut.cfg_sel),
        .pwm_sel       (u_dut.pwm_sel),
        .spi_sel       (u_dut.spi_sel),
        .uart_sel      (u_dut.uart_sel),
        .pwm_out       (pwm_out),
        .pwm_en        (u_dut.u_pwm_controller.en_reg),
        .pwm_duty      (u_dut.u_pwm_controller.duty_reg),
        .pwm_fault     (u_dut.u_pwm_controller.fault_reg),
        .pwm_failsafe  (u_dut.u_pwm_controller.failsafe_active),
        .fan_rpm       (fan_rpm),
        .spi_sclk      (spi_sclk),
        .spi_mosi      (spi_mosi),
        .spi_cs_n      (spi_cs_n),
        .spi_busy      (u_dut.u_spi_master.busy_reg),
        .spi_error     (u_dut.u_spi_master.error_reg),
        .spi_start     (u_dut.u_spi_master.start_pulse),
        .uart_tx_line  (uart_tx_line),
        .uart_tx_en    (u_dut.u_uart_top.tx_en),
        .uart_rx_valid (u_dut.u_uart_top.rx_valid_pulse),
        .uart_frame_err(u_dut.u_uart_top.frame_err_pulse)
    );

    // Latch that the bus_error pulse happened (it is a one-clock pulse)
    logic bus_error_seen = 1'b0;
    always @(posedge clk) if (bus_error === 1'b1) bus_error_seen <= 1'b1;

    // ===================================================================
    // Unit-level instances for PART B (declared before the tasks using them)
    // ===================================================================
    // ---- PWM ----
    logic          pwm_err_sel, pwm_err_we, pwm_err_re;
    logic [31:0]  pwm_err_addr, pwm_err_wdata, pwm_err_rdata;
    logic          pwm_err_out;
    logic [15:0]  pwm_err_rpm_in;

    pwm_controller #(.STALL_CYCLES (32), .RETRY_CYCLES (16)) u_pwm_err (
        .clk(clk), .rst_n(rst_n), .sel(pwm_err_sel), .addr(pwm_err_addr),
        .wdata(pwm_err_wdata), .we(pwm_err_we), .re(pwm_err_re),
        .rdata(pwm_err_rdata), .pwm_out(pwm_err_out), .rpm_in(pwm_err_rpm_in)
    );

    // ---- SPI ----
    logic          spi_err_sel, spi_err_we, spi_err_re;
    logic [31:0]  spi_err_addr, spi_err_wdata, spi_err_rdata;
    logic          spi_err_sclk, spi_err_mosi, spi_err_cs_n;

    spi_master u_spi_err (
        .clk(clk), .rst_n(rst_n), .sel(spi_err_sel), .addr(spi_err_addr),
        .wdata(spi_err_wdata), .we(spi_err_we), .re(spi_err_re),
        .rdata(spi_err_rdata), .sclk(spi_err_sclk), .mosi(spi_err_mosi),
        .miso(1'b0), .cs_n(spi_err_cs_n)
    );

    // ---- UART rx ----
    logic       uart_err_rx_line;
    logic [7:0] uart_err_rx_data;
    logic       uart_err_rx_valid;
    logic       uart_err_frame_error;

    uart_rx #(.CLKS_PER_BIT (UART_CLKS_PER_BIT)) u_uart_rx_err (
        .clk(clk), .rst_n(rst_n), .rx_line(uart_err_rx_line),
        .rx_data(uart_err_rx_data), .rx_valid(uart_err_rx_valid),
        .frame_error(uart_err_frame_error)
    );

    // Latch the one-cycle pulses so checks made after the fact can see them
    logic       uart_err_frame_error_seen;
    logic       uart_err_rx_valid_seen;
    logic [7:0] uart_err_rx_data_seen;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_err_frame_error_seen <= 1'b0;
            uart_err_rx_valid_seen    <= 1'b0;
            uart_err_rx_data_seen     <= 8'd0;
        end else begin
            if (uart_err_frame_error) uart_err_frame_error_seen <= 1'b1;
            if (uart_err_rx_valid) begin
                uart_err_rx_valid_seen <= 1'b1;
                uart_err_rx_data_seen  <= uart_err_rx_data;
            end
        end
    end

    // ===================================================================
    // PART A / B / C sequence
    // ===================================================================
    initial begin
        logic [7:0] uart_byte;
        bit         got_byte;

        rst_n = 1'b0;
        pwm_err_sel = 1'b0; pwm_err_we = 1'b0; pwm_err_re = 1'b0;
        pwm_err_addr = 32'd0; pwm_err_wdata = 32'd0; pwm_err_rpm_in = 16'd0;
        spi_err_sel = 1'b0; spi_err_we = 1'b0; spi_err_re = 1'b0;
        spi_err_addr = 32'd0; spi_err_wdata = 32'd0;
        uart_err_rx_line = 1'b1;
        repeat (5) @(posedge clk);

        // ---- Reset state ----
        $display("---- A0: reset state and configuration-SRAM preload ----");
        check_equal("Reset: PC = 0 after reset", u_dut.u_core.pc, 32'h0);
        check_true ("Reset: bus_error is low", (bus_error === 1'b0));
        check_true ("Reset: PWM disabled, duty = 0",
                    !u_dut.u_pwm_controller.en_reg && u_dut.u_pwm_controller.duty_reg == 8'd0);
        check_true ("Reset: SPI CS_N high, SCLK low", spi_cs_n === 1'b1 && spi_sclk === 1'b0);
        check_true ("Reset: UART TX idle high", uart_tx_line === 1'b1);
        check_true ("Reset: fan RPM = 0", fan_rpm == 16'd0);
        // testbench preloads the configuration SRAM from config_data.hex
        check_equal("CFG preload: PROFILE_TEMP_LOW  (0x28)", u_dut.u_config_sram.mem[0], 32'h0000_0028);
        check_equal("CFG preload: PROFILE_DUTY_LOW  (0x3C)", u_dut.u_config_sram.mem[1], 32'h0000_003C);
        check_equal("CFG preload: PROFILE_TEMP_HIGH (0x46)", u_dut.u_config_sram.mem[2], 32'h0000_0046);
        check_equal("CFG preload: PROFILE_DUTY_HIGH (0xC8)", u_dut.u_config_sram.mem[3], 32'h0000_00C8);
        check_equal("CFG preload: PROFILE_ID (0xCAFEDA7A)",  u_dut.u_config_sram.mem[4], 32'hCAFE_DA7A);

        @(negedge clk);
        rst_n = 1'b1;

        // The terminal (host) sends a byte to the DUT while the core waits in its RX poll loop
        fork
            begin
                #8000;
                u_uart_terminal.send_byte(8'h5A);
            end
        join_none

        #20000; // 20 us
        $display("---- A1: program-driven full-SoC tests ----");

        check_equal("SRAM: DMEM[0] written by core (=123)", u_dut.u_dmem.mem[0], 32'd123);

        check_equal("PWM: PWM_DUTY register set to 128", {24'd0, u_dut.u_pwm_controller.duty_reg}, 32'd128);
        check_true ("PWM: PWM enabled (en_reg = 1)", u_dut.u_pwm_controller.en_reg);

        // config SRAM read by the core (bus read path to config SRAM)
        check_equal("CFG read: core read PROFILE_ID -> DMEM[5]", u_dut.u_dmem.mem[5], 32'hCAFE_DA7A);

        // SPI: 4 transfers, profile bytes loaded into DMEM and CONFIG SRAM
        check_equal("SPI: 4 transfers completed", spi_transfer_count, 4);
        check_equal("SPI: profile byte 0 received (DMEM[1])", u_dut.u_dmem.mem[1], 32'h0000_00DE);
        check_equal("SPI: profile byte 1 received (DMEM[2])", u_dut.u_dmem.mem[2], 32'h0000_00AD);
        check_equal("SPI: profile byte 2 received (DMEM[3])", u_dut.u_dmem.mem[3], 32'h0000_00BE);
        check_equal("SPI: profile byte 3 received (DMEM[4])", u_dut.u_dmem.mem[4], 32'h0000_00EF);
        check_equal("SPI: slave logged core's TX byte 0xA5 (xfer 0)", {24'd0, spi_rx_log[0]}, 32'hA5);
        check_equal("SPI: slave logged core's TX byte 0xA5 (xfer 3)", {24'd0, spi_rx_log[3]}, 32'hA5);
        check_equal("PROFILE LOAD: CFG[0] = 0xDE", u_dut.u_config_sram.mem[0], 32'h0000_00DE);
        check_equal("PROFILE LOAD: CFG[1] = 0xAD", u_dut.u_config_sram.mem[1], 32'h0000_00AD);
        check_equal("PROFILE LOAD: CFG[2] = 0xBE", u_dut.u_config_sram.mem[2], 32'h0000_00BE);
        check_equal("PROFILE LOAD: CFG[3] = 0xEF", u_dut.u_config_sram.mem[3], 32'h0000_00EF);
        check_equal("PROFILE LOAD: CFG[4] (ID) untouched", u_dut.u_config_sram.mem[4], 32'hCAFE_DA7A);

        // UART transmit: core -> terminal
        got_byte = u_uart_terminal.get_next_byte(uart_byte);
        check_true ("UART TX: terminal received a byte from core", got_byte);
        if (got_byte)
            check_equal("UART TX: received byte matches 'A' (0x41)", {24'd0, uart_byte}, 32'h41);
        // UART receive: terminal -> core (core polled RX_VALID, read RXDATA -> DMEM[6])
        check_equal("UART RX: core received 0x5A from terminal", u_dut.u_dmem.mem[6], 32'h0000_005A);

        // Unmapped access
        check_true ("BUS: bus_error raised on unmapped access", bus_error_seen);
        check_equal("BUS: unmapped read returned 0xDEADBEEF", u_dut.u_dmem.mem[7], 32'hDEAD_BEEF);

        #20000;
        check_true ("PWM: fan RPM > 0 after enable (fan spinning up)", (fan_rpm > 16'd0));
        check_true ("PWM: PWM output toggles (pwm_out active in window)",
                    u_fan_model.duty_measured > 9'd0);
        check_equal("PWM: measured duty (fan model) = programmed 128", {23'd0, u_fan_model.duty_measured}, 32'd128);

        $display("\n===== PART A (Full SoC, normal operation) complete =====\n");

        // ---- Part B ----
        run_pwm_failsafe_tests();
        run_spi_start_while_busy_error_test();
        run_uart_frame_error_test();
        run_uart_good_frame_test();

        // ---- Part C ----
        run_reset_midway_test();

        // ---- Assertions ----
        check_equal("SVA: zero assertion failures", u_sva.fail_count, 0);

        $display("\n===================================================");
        $display(" TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("===================================================\n");
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: %0d TEST(S) FAILED", fail_count);

        $finish;
    end

    // Safety timeout in case a wait loop never completes
    initial begin
        #1000000;
        $display("[FAIL] TIMEOUT: simulation did not finish in time");
        fail_count++;
        $finish;
    end

    // ===================================================================
    // PART B tasks
    // ===================================================================
    // Bus stimulus is driven on the FALLING clock edge so the DUT (rising-edge flops)
    // never races with the testbench.
    task automatic pwm_wr(input [3:0] off, input [31:0] data);
        begin
            @(negedge clk);
            pwm_err_sel = 1'b1; pwm_err_we = 1'b1; pwm_err_addr = {28'd0, off}; pwm_err_wdata = data;
            @(negedge clk);
            pwm_err_sel = 1'b0; pwm_err_we = 1'b0;
        end
    endtask

    task automatic pwm_rd(input [3:0] off, output [31:0] data);
        begin
            @(negedge clk);
            pwm_err_sel = 1'b1; pwm_err_re = 1'b1; pwm_err_addr = {28'd0, off};
            #1 data = pwm_err_rdata;          // combinational read data
            @(negedge clk);
            pwm_err_sel = 1'b0; pwm_err_re = 1'b0;
        end
    endtask

    task automatic run_pwm_failsafe_tests();
        logic [31:0] st;
        int          i;
        bit          drive_seen;
        begin
            $display("---- B1: PWM stall -> FAULT -> fail-safe -> recovery ----");
            pwm_err_rpm_in = 16'd0;                 // jammed fan: RPM never rises
            pwm_wr(4'h4, 32'd100);                  // duty
            pwm_wr(4'h0, 32'h1);                    // enable

            // wait for the fault (STALL_CYCLES = 32)
            for (i = 0; i < 80 && !u_pwm_err.fault_reg; i++) @(posedge clk);
            pwm_rd(4'h8, st);
            check_true("PWM stall: FAULT bit set on stalled fan", st[1]);
            check_true("PWM stall: FAILSAFE bit set (drive removed)", st[2]);

            // While in fail-safe the output must stay low
            drive_seen = 1'b0;
            for (i = 0; i < 10; i++) begin
                @(posedge clk);
                if (u_pwm_err.failsafe_active && pwm_err_out) drive_seen = 1'b1;
            end
            check_true("PWM fail-safe: no drive while in fail-safe", !drive_seen);

            // Fan recovers (e.g. obstruction removed): fault must clear by itself
            pwm_err_rpm_in = 16'd400;
            for (i = 0; i < 100 && u_pwm_err.fault_reg; i++) @(posedge clk);
            pwm_rd(4'h8, st);
            check_true("PWM recovery: FAULT cleared after fan spins again", !st[1]);
            check_true("PWM recovery: FAILSAFE released", !st[2]);
            check_true("PWM recovery: RUNNING bit set", st[0]);

            // Disabling the PWM clears any fault
            pwm_err_rpm_in = 16'd0;
            pwm_wr(4'h0, 32'h0);
            repeat (5) @(posedge clk);

            // Duty = 0 is an intentional 'off', not a stall
            $display("---- B1b: duty = 0 must not raise a stall fault ----");
            pwm_wr(4'h4, 32'd0);
            pwm_wr(4'h0, 32'h1);
            repeat (80) @(posedge clk);
            pwm_rd(4'h8, st);
            check_true("PWM duty=0: no FAULT although RPM = 0", !st[1]);
            pwm_wr(4'h0, 32'h0);

            // Soft reset clears a fault
            $display("---- B1c: SOFT_RESET clears a fault ----");
            pwm_wr(4'h4, 32'd100);
            pwm_wr(4'h0, 32'h1);
            for (i = 0; i < 80 && !u_pwm_err.fault_reg; i++) @(posedge clk);
            check_true("PWM soft-reset: fault present before reset", u_pwm_err.fault_reg);
            pwm_wr(4'h0, 32'h3);                    // EN=1 + SOFT_RESET
            repeat (3) @(posedge clk);
            check_true("PWM soft-reset: FAULT cleared by SOFT_RESET", !u_pwm_err.fault_reg);
            pwm_wr(4'h0, 32'h0);
        end
    endtask

    // -------------------------------------------------------------
    // B2. SPI "start while busy" protocol error
    // -------------------------------------------------------------
    task automatic run_spi_start_while_busy_error_test();
        begin
            $display("---- B2: SPI start-while-busy error case ----");
            @(negedge clk);
            spi_err_sel = 1'b1; spi_err_we = 1'b1;
            spi_err_addr = 32'h0; spi_err_wdata = 32'h1;   // legitimate START (sampled at next rising edge)
            @(negedge clk);                                // second START while the transfer is running
            @(negedge clk);
            spi_err_we = 1'b0;
            repeat (4) @(negedge clk);
            spi_err_re = 1'b1; spi_err_addr = 32'hC;       // read SPI_STATUS
            #1 check_true("SPI error case: ERROR bit set on start-while-busy", spi_err_rdata[2]);
            @(negedge clk);
            spi_err_re = 1'b0; spi_err_sel = 1'b0;
            repeat (200) @(posedge clk);                   // let the transfer finish
        end
    endtask

    // -------------------------------------------------------------
    // B3. UART framing error
    // -------------------------------------------------------------
    task automatic run_uart_frame_error_test();
        int i;
        begin
            $display("---- B3: UART framing error case ----");
            uart_err_rx_line = 1'b1;
            @(posedge clk);
            uart_err_rx_line = 1'b0;                       // start bit
            #(UART_BIT_NS);
            for (i = 0; i < 8; i++) begin
                uart_err_rx_line = 1'b1;                   // data bits (all 1s)
                #(UART_BIT_NS);
            end
            uart_err_rx_line = 1'b0;                       // BAD stop bit
            #(UART_BIT_NS);
            uart_err_rx_line = 1'b1;
            #(UART_BIT_NS);
            check_true("UART error case: frame_error asserted on bad stop bit", uart_err_frame_error_seen);
            check_true("UART error case: no rx_valid for a bad frame", !uart_err_rx_valid_seen);
        end
    endtask

    // -------------------------------------------------------------
    // B4. UART good frame receive (positive path)
    // -------------------------------------------------------------
    task automatic run_uart_good_frame_test();
        int i;
        logic [7:0] data = 8'hC3;
        begin
            $display("---- B4: UART good-frame receive ----");
            uart_err_rx_line = 1'b1;
            #(UART_BIT_NS);
            uart_err_rx_line = 1'b0;                       // start
            #(UART_BIT_NS);
            for (i = 0; i < 8; i++) begin
                uart_err_rx_line = data[i];
                #(UART_BIT_NS);
            end
            uart_err_rx_line = 1'b1;                       // stop
            #(2 * UART_BIT_NS);
            check_true ("UART RX unit: rx_valid pulsed for a good frame", uart_err_rx_valid_seen);
            check_equal("UART RX unit: received data = 0xC3", {24'd0, uart_err_rx_data_seen}, 32'hC3);
        end
    endtask

    // ===================================================================
    // PART C: reset asserted in the middle of operation
    // ===================================================================
    task automatic run_reset_midway_test();
        logic [31:0] pc_before;
        begin
            $display("---- C: reset applied in the middle of operation ----");
            pc_before = u_dut.u_core.pc;
            check_true("Mid-reset: design was running (PWM enabled)", u_dut.u_pwm_controller.en_reg);
            #3;                                             // not aligned to a clock edge: async reset
            rst_n = 1'b0;
            #1;
            check_equal("Mid-reset: PC returns to 0 immediately (async)", u_dut.u_core.pc, 32'h0);
            check_true ("Mid-reset: PWM disabled again", !u_dut.u_pwm_controller.en_reg);
            check_equal("Mid-reset: PWM duty cleared", {24'd0, u_dut.u_pwm_controller.duty_reg}, 32'h0);
            check_true ("Mid-reset: SPI CS_N released", spi_cs_n === 1'b1);
            check_true ("Mid-reset: UART TX idle", uart_tx_line === 1'b1);
            check_equal("Mid-reset: fan RPM cleared", {16'd0, fan_rpm}, 32'h0);
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (5) @(posedge clk);
            check_true("Mid-reset: core restarts fetching after release", u_dut.u_core.pc != 32'h0);
        end
    endtask

    // -----------------------------------------------------------------
    // Waveform dump
    // -----------------------------------------------------------------
    initial begin
        $dumpfile("tb_soc_top.vcd");
        $dumpvars(0, tb_soc_top);
    end

endmodule
