# run_tb.do - RTL directed testbenches (plain, no coverage).  Questa/ModelSim.
# Launch Questa with the PROJECT ROOT as working directory, then:   do run_tb.do
#   1) tb_soc_top    : full-SoC system tests + error cases + reset tests + assertions
#   2) tb_core_instr : all 37 RV32I instructions vs. the golden ISS results
quit -sim
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog -sv -timescale 1ns/1ps -f sim/tb_filelist.f

foreach tb {tb_soc_top tb_core_instr} {
    vsim -voptargs=+acc work.$tb
    run -all
    quit -sim
}
