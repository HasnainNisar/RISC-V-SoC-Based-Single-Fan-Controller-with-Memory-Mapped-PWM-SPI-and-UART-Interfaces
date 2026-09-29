# run_cov.do - merge all cov/*.ucdb and produce coverage reports (code, functional, assertions).
# Working directory = PROJECT ROOT.   Usage:  do run_cov.do
set dbs {}
foreach f [glob -nocomplain cov/*.ucdb] {
    if {[file tail $f] ne "merged.ucdb"} { lappend dbs $f }
}
if {[llength $dbs] == 0} { echo "No cov/*.ucdb files found - run run_tb.do / run_uvm.do / run_regress.do first"; return }
vcover merge -out cov/merged.ucdb {*}$dbs
vcover report -details -output cov/coverage_report.txt cov/merged.ucdb
vcover report -html -htmldir cov/html -details cov/merged.ucdb
vcover stats cov/merged.ucdb
echo "Coverage report: cov/coverage_report.txt   HTML: cov/html/index.html"
