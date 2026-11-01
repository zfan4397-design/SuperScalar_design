$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$checkRoot = Join-Path $projectRoot 'build/ctrl_unit_scaffold_check'
[IO.Directory]::CreateDirectory($checkRoot) | Out-Null
Push-Location $checkRoot
try {
    & 'D:\Vivado\2023.2\bin\xvlog.bat' --work ctrl_unit_scaffold `
        -i "$projectRoot/vpackage" `
        "$projectRoot/build/vivado/mysuperscaler.srcs/sources_1/new/ctrl_unit.v"
    if ($LASTEXITCODE -ne 0) { throw 'CTRL_UNIT scaffold Verilog compilation failed.' }
    Write-Output 'CTRL_UNIT_SCAFFOLD_COMPILE_PASS (syntax only; core TODO groups remain)'
} finally {
    Pop-Location
}
