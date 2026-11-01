$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$checkRoot = Join-Path $projectRoot 'build/retire_ctrl_scaffold_check'
$sourceFile = Join-Path $projectRoot 'build/vivado/mysuperscaler.srcs/sources_1/new/retire_ctrl.v'
if (!(Test-Path -LiteralPath $sourceFile)) { throw "Missing Vivado source: $sourceFile" }
[IO.Directory]::CreateDirectory($checkRoot) | Out-Null
Push-Location $checkRoot
try {
    # Plain Verilog syntax only; the core TODOs intentionally remain unfinished.
    & 'D:\Vivado\2023.2\bin\xvlog.bat' --work retire_ctrl_scaffold `
        -i "$projectRoot/vpackage" $sourceFile
    if ($LASTEXITCODE -ne 0) { throw 'retire_ctrl scaffold Verilog compilation failed.' }
    Write-Output 'RETIRE_CTRL_SCAFFOLD_COMPILE_PASS (syntax only; core TODOs remain)'
} finally {
    Pop-Location
}
