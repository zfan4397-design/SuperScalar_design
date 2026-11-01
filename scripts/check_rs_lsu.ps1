$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$checkRoot = Join-Path $projectRoot 'build/rs_lsu_scaffold_check'
[IO.Directory]::CreateDirectory($checkRoot) | Out-Null
$guiSource = Join-Path $projectRoot 'build/vivado/mysuperscaler.srcs/sources_1/new/rs_lsu_queue.v'
$mainSource = Join-Path $projectRoot 'rtl/utils/rs_lsu_queue.v'
if (Test-Path -LiteralPath $guiSource) {
    $mainSource = $guiSource
}
$sourceFiles = @($mainSource)
if (![regex]::IsMatch([IO.File]::ReadAllText($mainSource), '(?m)^\s*module\s+age_matrix_arbiter\b')) {
    $sourceFiles = @((Join-Path $projectRoot 'rtl/utils/age_matrix_arbiter.v')) + $sourceFiles
}
Write-Output "Checking LSU source: $mainSource"
Push-Location $checkRoot
try {
    & 'D:\Vivado\2023.2\bin\xvlog.bat' --work lsu_scaffold -i "$projectRoot/vpackage" @sourceFiles
    if ($LASTEXITCODE -ne 0) { throw 'LSU scaffold Verilog compilation failed.' }
    Write-Output 'LSU_SCAFFOLD_COMPILE_PASS (syntax only; TODOs remain)'
} finally {
    Pop-Location
}
