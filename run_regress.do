# run_regress.do - full regression WITH code/functional/assertion coverage, then merge + report.
# NOTE: needs a Questa licence that includes coverage. Working directory = PROJECT ROOT.
# Usage: do run_regress.do    Output: cov/*.ucdb, cov/merged.ucdb, cov/coverage_report.txt, cov/html/
quit -sim
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
file mkdir cov
foreach f [glob -nocomplain cov/*.ucdb] { file delete $f }

# ---- compile once: DUT with code coverage; models/TB/UVM without ----
vlog -sv -timescale 1ns/1ps +cover=bcesf -f filelist.f
vlog -sv -timescale 1ns/1ps +incdir+uvm sim/models/fan_model.sv sim/models/spi_slave_model.sv sim/models/uart_terminal_model.sv sim/soc_assertions.sv sim/tb_soc_top.sv sim/tb_core_instr.sv uvm/soc_if.sv uvm/uvm_pkg_includes.sv uvm/tb_top_uvm.sv

# ---- directed testbenches ----
foreach tb {tb_soc_top tb_core_instr} {
    vsim -coverage -voptargs="+acc +cover=bcesft" work.$tb
    run -all
    coverage save cov/$tb.ucdb
    quit -sim
}

# ---- UVM tests ----
foreach tn {normal_test error_test failsafe_test regression_test core_instr_test} {
    set extra ""
    if {$tn eq "core_instr_test"} { set extra "+IMEM=instr_test.hex" }
    vsim -coverage -voptargs="+acc +cover=bcesft" work.tb_top_uvm +UVM_TESTNAME=$tn +UVM_NO_RELNOTES {*}$extra
    run -all
    coverage save cov/uvm_$tn.ucdb
    quit -sim
}

# ---- merge + report ----
do run_cov.do
