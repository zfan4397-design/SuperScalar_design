$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$referenceRoot = 'D:\zz\superscalercore'
$vivadoBin = 'D:\Vivado\2023.2\bin'
$checkRoot = Join-Path $projectRoot 'build/rs_mul_check'
[IO.Directory]::CreateDirectory($checkRoot) | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
$savedTemp = $env:TEMP
$savedTmp = $env:TMP
$taskTemp = Join-Path $checkRoot 'tmp'
[IO.Directory]::CreateDirectory($taskTemp) | Out-Null
$env:TEMP = $taskTemp
$env:TMP = $taskTemp
$referenceMul = [IO.File]::ReadAllText((Join-Path $referenceRoot 'vsrc/utils/rs_mul_queue.sv'))
$referenceMul = $referenceMul.Replace('module rs_mul_queue #(', 'module rs_mul_queue_reference #(')
$referenceMul = $referenceMul.Replace('age_matrix_arbiter #(', 'age_matrix_arbiter_reference #(')
$referenceArb = [IO.File]::ReadAllText((Join-Path $referenceRoot 'vsrc/utils/age_matrix_arbiter.sv'))
$referenceArb = "import config_pkg::*;`n" + $referenceArb.Replace('age_matrix_arbiter', 'age_matrix_arbiter_reference')
[IO.File]::WriteAllText((Join-Path $checkRoot 'rs_mul_queue_reference.sv'), $referenceMul, $utf8)
[IO.File]::WriteAllText((Join-Path $checkRoot 'age_matrix_arbiter_reference.sv'), $referenceArb, $utf8)
Push-Location $checkRoot
try {
    # No --sv here: the delivered RTL must compile as ordinary Verilog.
    & "$vivadoBin/xvlog.bat" --work mul_dut -i "$projectRoot/vpackage" `
        "$projectRoot/rtl/utils/age_matrix_arbiter.v" "$projectRoot/rtl/utils/rs_mul_queue.v"
    if ($LASTEXITCODE -ne 0) { throw 'MUL Verilog compilation failed.' }
    & "$vivadoBin/xvlog.bat" --sv --work mul_test `
        "$referenceRoot/vpackage/config_pkg.sv" "$referenceRoot/vpackage/issue_pkg.sv" `
        './age_matrix_arbiter_reference.sv' './rs_mul_queue_reference.sv' `
        "$projectRoot/tests/issue/tb_rs_mul_compare.sv"
    if ($LASTEXITCODE -ne 0) { throw 'MUL reference/testbench compilation failed.' }
    & "$vivadoBin/xelab.bat" --debug typical -L mul_dut mul_test.tb_rs_mul_compare -s rs_mul_compare
    if ($LASTEXITCODE -ne 0) { throw 'MUL comparison elaboration failed.' }
    & "$vivadoBin/xsim.bat" rs_mul_compare --runall --log compare_sim.log
    if ($LASTEXITCODE -ne 0) { throw 'MUL comparison simulation failed.' }
    $simLog = [IO.File]::ReadAllText((Join-Path $checkRoot 'compare_sim.log'))
    if ($simLog -notmatch 'RS_MUL_REFERENCE_COMPARE_PASS' -or $simLog -match 'Fatal:|TIMEOUT') {
        throw 'MUL reference comparison failed; see compare_sim.log.'
    }
} finally {
    Pop-Location
    $env:TEMP = $savedTemp
    $env:TMP = $savedTmp
}
