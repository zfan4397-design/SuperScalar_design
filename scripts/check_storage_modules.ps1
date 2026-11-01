$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$checkRoot = Join-Path $projectRoot 'build/storage_scaffold_check'
[IO.Directory]::CreateDirectory($checkRoot) | Out-Null
Push-Location $checkRoot
try {
    & 'D:\Vivado\2023.2\bin\xvlog.bat' --work storage_dut `
        -i "$projectRoot/vpackage" `
        "$projectRoot/build/vivado/mysuperscaler.srcs/sources_1/new/store_buffer.v" `
        "$projectRoot/build/vivado/mysuperscaler.srcs/sources_1/new/arf.v"
    if ($LASTEXITCODE -ne 0) { throw 'Storage module Verilog compilation failed.' }
    Write-Output 'STORAGE_MODULES_COMPILE_PASS (store_buffer core TODOs remain)'
} finally {
    Pop-Location
}
