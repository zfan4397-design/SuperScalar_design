param([switch]$Before)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$referenceRoot = 'D:\zz\superscalercore'
$vivadoBin = 'D:\Vivado\2023.2\bin'
$checkRoot = Join-Path $projectRoot 'build/rename_review'
$runRoot = Join-Path $checkRoot $(if ($Before) { 'before_run' } else { 'after_run' })
[IO.Directory]::CreateDirectory($runRoot) | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
$savedTemp = $env:TEMP
$savedTmp = $env:TMP
$taskTemp = Join-Path $runRoot 'tmp'
[IO.Directory]::CreateDirectory($taskTemp) | Out-Null
$env:TEMP = $taskTemp
$env:TMP = $taskTemp
foreach ($name in @('rat', 'freelist')) {
    $source = [IO.File]::ReadAllText((Join-Path $referenceRoot "vsrc/utils/$name.sv"))
    $source = [regex]::Replace($source, "\bmodule\s+$name\b", "module ${name}_reference")
    [IO.File]::WriteAllText((Join-Path $runRoot "${name}_reference.sv"), $source, $utf8)
}
$dutRoot = if ($Before) { Join-Path $checkRoot 'before' } else { Join-Path $projectRoot 'rtl/utils' }
Push-Location $runRoot
try {
    & "$vivadoBin/xvlog.bat" --work rename_dut -i "$projectRoot/vpackage" "$dutRoot/rat.v" "$dutRoot/freelist.v"
    if ($LASTEXITCODE -ne 0) { throw 'Verilog compilation failed.' }
    & "$vivadoBin/xvlog.bat" --sv --work rename_test `
        "$referenceRoot/vpackage/config_pkg.sv" "$referenceRoot/vpackage/rat_pkg.sv" "$referenceRoot/vpackage/rob_pkg.sv" `
        './rat_reference.sv' './freelist_reference.sv' "$projectRoot/tests/rename/tb_rename_review.sv"
    if ($LASTEXITCODE -ne 0) { throw 'Reference/testbench compilation failed.' }
    & "$vivadoBin/xelab.bat" --debug typical -L rename_dut rename_test.tb_rename_review -s rename_review
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed.' }
    & "$vivadoBin/xsim.bat" rename_review --runall --log review_sim.log
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed.' }
    $simLog = [IO.File]::ReadAllText((Join-Path $runRoot 'review_sim.log'))
    if ($simLog -notmatch 'RENAME_REVIEW_PASS' -or $simLog -match 'Fatal:|TIMEOUT') {
        throw 'Reference comparison failed; see review_sim.log.'
    }
} finally {
    Pop-Location
    $env:TEMP = $savedTemp
    $env:TMP = $savedTmp
}
