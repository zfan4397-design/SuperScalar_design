$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$checkRoot = Join-Path $projectRoot 'build/read_oprand_scaffold_check'
$sourceFile = Join-Path $projectRoot 'build/vivado/mysuperscaler.srcs/sources_1/new/read_oprand.v'
if (!(Test-Path -LiteralPath $sourceFile)) { throw "Missing Vivado source: $sourceFile" }
[IO.Directory]::CreateDirectory($checkRoot) | Out-Null
Push-Location $checkRoot
try {
    # Syntax only: the learner intentionally owns the core TODO assignments.
    & 'D:\Vivado\2023.2\bin\xvlog.bat' --work read_oprand_scaffold `
        -i "$projectRoot/vpackage" $sourceFile
    if ($LASTEXITCODE -ne 0) { throw 'read_oprand scaffold Verilog compilation failed.' }
    Write-Output 'READ_OPRAND_SCAFFOLD_COMPILE_PASS (syntax only; core TODOs remain)'
} finally {
    Pop-Location
}
