# run_uvm.do - one UVM test (Questa).  Working directory = PROJECT ROOT.
#   Usage:  do run_uvm.do <test>
#   tests: normal_test | error_test | failsafe_test | regression_test | core_instr_test
quit -sim
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv -timescale 1ns/1ps +incdir+uvm -f uvm/tb_filelist_uvm.f

set tn normal_test
if {$argc > 0} { set tn $1 }
set extra ""
if {$tn eq "core_instr_test"} { set extra "+IMEM=instr_test.hex" }
vsim -voptargs=+acc work.tb_top_uvm +UVM_TESTNAME=$tn +UVM_NO_RELNOTES {*}$extra
run -all
