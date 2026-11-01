$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$checkRoot = Join-Path $projectRoot 'build/fu_mem_scaffold_check'
[IO.Directory]::CreateDirectory($checkRoot) | Out-Null
Push-Location $checkRoot
try {
    & 'D:\Vivado\2023.2\bin\xvlog.bat' --work fu_mem_scaffold `
        -i "$projectRoot/vpackage" `
        "$projectRoot/build/vivado/mysuperscaler.srcs/sources_1/new/store_buffer.v" `
        "$projectRoot/build/vivado/mysuperscaler.srcs/sources_1/new/dff_fu.v" `
        "$projectRoot/build/vivado/mysuperscaler.srcs/sources_1/new/fu_mem.v"
    if ($LASTEXITCODE -ne 0) { throw 'FU_MEM scaffold Verilog compilation failed.' }
    Write-Output 'FU_MEM_SCAFFOLD_COMPILE_PASS (syntax only; core TODOs remain)'
} finally {
    Pop-Location
}
