param([switch]$Before)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoBin = 'D:\Vivado\2023.2\bin'
$runName = if ($Before) { 'before_run' } else { 'after_run' }
$checkRoot = Join-Path $projectRoot "build/ifq_check/$runName"
[IO.Directory]::CreateDirectory($checkRoot) | Out-Null
$savedTemp = $env:TEMP
$savedTmp = $env:TMP
$taskTemp = Join-Path $checkRoot 'tmp'
[IO.Directory]::CreateDirectory($taskTemp) | Out-Null
$env:TEMP = $taskTemp
$env:TMP = $taskTemp
$reference = [IO.File]::ReadAllText('D:\zz\superscalercore\vsrc\utils\ifq.sv')
$reference = '`timescale 1ns/1ps' + "`n" + $reference.Replace('module ifq #(', 'module ifq_reference #(')
[IO.File]::WriteAllText((Join-Path $checkRoot 'ifq_reference.sv'), $reference, (New-Object Text.UTF8Encoding($false)))
$sourceFile = if ($Before) { Join-Path $projectRoot 'build/ifq_check/before_ifq.v' } else {
    Join-Path $projectRoot 'build/vivado/mysuperscaler.srcs/sources_1/new/ifq.v'
}
Push-Location $checkRoot
try {
    & "$vivadoBin/xvlog.bat" --work ifq_dut -i "$projectRoot/vpackage" $sourceFile
    if ($LASTEXITCODE -ne 0) { throw 'IFQ Verilog compilation failed.' }
    & "$vivadoBin/xvlog.bat" --sv --work ifq_test `
        D:/zz/superscalercore/vpackage/config_pkg.sv ./ifq_reference.sv `
        "$projectRoot/tests/ifq/tb_ifq_review.sv"
    if ($LASTEXITCODE -ne 0) { throw 'IFQ reference/testbench compilation failed.' }
    & "$vivadoBin/xelab.bat" --debug typical -L ifq_dut ifq_test.tb_ifq_review -s ifq_review
    if ($LASTEXITCODE -ne 0) { throw 'IFQ elaboration failed.' }
    & "$vivadoBin/xsim.bat" ifq_review --runall --log review_sim.log
    if ($LASTEXITCODE -ne 0) { throw 'IFQ simulation failed.' }
    $simLog = [IO.File]::ReadAllText((Join-Path $checkRoot 'review_sim.log'))
    if ($simLog -notmatch 'IFQ_REFERENCE_AND_MODEL_PASS' -or $simLog -match 'Fatal:|TIMEOUT') {
        throw 'IFQ reference/model comparison failed; see review_sim.log.'
    }
} finally {
    Pop-Location
    $env:TEMP = $savedTemp
    $env:TMP = $savedTmp
}
