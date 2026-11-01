$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$checkRoot = Join-Path $projectRoot 'build/clint_scaffold_check'
$sourceFile = Join-Path $projectRoot 'build/vivado/mysuperscaler.srcs/sources_1/new/clint.v'
if (!(Test-Path -LiteralPath $sourceFile)) { throw "Missing Vivado source: $sourceFile" }
[IO.Directory]::CreateDirectory($checkRoot) | Out-Null
Push-Location $checkRoot
try {
    & 'D:\Vivado\2023.2\bin\xvlog.bat' --work clint_scaffold -i "$projectRoot/vpackage" $sourceFile
    if ($LASTEXITCODE -ne 0) { throw 'CLINT plain-Verilog syntax compilation failed.' }
    Write-Output 'CLINT_SCAFFOLD_COMPILE_PASS (syntax only; core TODOs remain)'
} finally { Pop-Location }
