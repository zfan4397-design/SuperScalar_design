$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$referenceRoot = 'D:/zz/superscalercore'
$checkRoot = Join-Path $projectRoot 'build/arf_check'
$vivadoBin = 'D:/Vivado/2023.2/bin'
[IO.Directory]::CreateDirectory($checkRoot) | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
$referenceArf = [IO.File]::ReadAllText((Join-Path $referenceRoot 'vsrc/utils/arf.sv'))
$referenceArf = $referenceArf.Replace('module arf #(', 'module arf_reference #(')
$referenceArf = '`timescale 1ns/1ps' + "`n" + $referenceArf
[IO.File]::WriteAllText((Join-Path $checkRoot 'arf_reference.sv'), $referenceArf, $utf8)
$savedTemp = $env:TEMP
$savedTmp = $env:TMP
$taskTemp = Join-Path $checkRoot 'tmp'
[IO.Directory]::CreateDirectory($taskTemp) | Out-Null
$env:TEMP = $taskTemp
$env:TMP = $taskTemp
Push-Location $checkRoot
try {
    & "$vivadoBin/xvlog.bat" --work arf_dut -i "$projectRoot/vpackage" `
        "$projectRoot/build/vivado/mysuperscaler.srcs/sources_1/new/arf.v"
    if ($LASTEXITCODE -ne 0) { throw 'ARF Verilog compilation failed.' }
    & "$vivadoBin/xvlog.bat" --sv --work arf_test `
        "$referenceRoot/vpackage/config_pkg.sv" "$referenceRoot/vpackage/retire_pkg.sv" `
        './arf_reference.sv' "$projectRoot/tests/retire/tb_arf_compare.sv"
    if ($LASTEXITCODE -ne 0) { throw 'ARF reference/testbench compilation failed.' }
    & "$vivadoBin/xelab.bat" --debug typical -L arf_dut arf_test.tb_arf_compare -s arf_compare
    if ($LASTEXITCODE -ne 0) { throw 'ARF elaboration failed.' }
    & "$vivadoBin/xsim.bat" arf_compare --runall --log compare_sim.log
    if ($LASTEXITCODE -ne 0) { throw 'ARF simulation failed.' }
    $simLog = [IO.File]::ReadAllText((Join-Path $checkRoot 'compare_sim.log'))
    if ($simLog -notmatch 'ARF_REFERENCE_AND_MODEL_PASS' -or $simLog -match 'Fatal:|TIMEOUT') {
        throw 'ARF comparison failed; see compare_sim.log.'
    }
} finally {
    Pop-Location
    $env:TEMP = $savedTemp
    $env:TMP = $savedTmp
}
