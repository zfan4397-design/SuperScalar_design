$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$checkRoot = Join-Path $projectRoot 'build/fu_mem_scaffold_check'
$vivadoBin = 'D:/Vivado/2023.2/bin'
& 'D:/python.exe' "$checkRoot/make_dff_test.py"
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare DFF_FU comparison.' }
$savedTemp = $env:TEMP
$savedTmp = $env:TMP
$taskTemp = Join-Path $checkRoot 'tmp'
[IO.Directory]::CreateDirectory($taskTemp) | Out-Null
$env:TEMP = $taskTemp
$env:TMP = $taskTemp
Push-Location $checkRoot
try {
    & "$vivadoBin/xvlog.bat" --work dff_fu_dut -i "$projectRoot/vpackage" `
        "$projectRoot/build/vivado/mysuperscaler.srcs/sources_1/new/dff_fu.v"
    if ($LASTEXITCODE -ne 0) { throw 'DFF_FU Verilog compilation failed.' }
    & "$vivadoBin/xvlog.bat" --sv --work dff_fu_test `
        './config_pkg_test.sv' `
        './dff_fu_reference.sv' './tb_dff_fu_compare.sv'
    if ($LASTEXITCODE -ne 0) { throw 'DFF_FU reference/testbench compilation failed.' }
    & "$vivadoBin/xelab.bat" --debug typical -L dff_fu_dut dff_fu_test.tb_dff_fu_compare -s dff_fu_compare
    if ($LASTEXITCODE -ne 0) { throw 'DFF_FU elaboration failed.' }
    & "$vivadoBin/xsim.bat" dff_fu_compare --runall --log dff_compare_sim.log
    if ($LASTEXITCODE -ne 0) { throw 'DFF_FU simulation failed.' }
    $simLog = [IO.File]::ReadAllText((Join-Path $checkRoot 'dff_compare_sim.log'))
    if ($simLog -notmatch 'DFF_FU_REFERENCE_COMPARE_PASS' -or $simLog -match 'Fatal:|TIMEOUT') {
        throw 'DFF_FU comparison failed; see dff_compare_sim.log.'
    }
} finally {
    Pop-Location
    $env:TEMP = $savedTemp
    $env:TMP = $savedTmp
}
