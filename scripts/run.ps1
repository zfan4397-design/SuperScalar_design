[CmdletBinding()]
param(
    [ValidateSet('doctor','project','sim','synth','definitions-check','reference-check','open-vivado')]
    [string]$Action = 'doctor'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoRoot = 'D:\Vivado\2023.2'
if ($env:MYSUPERSCALER_VIVADO) { $vivadoRoot = $env:MYSUPERSCALER_VIVADO }
$referenceRoot = 'D:\zz\superscalercore'
$vivadoBat = Join-Path $vivadoRoot 'bin\vivado.bat'
$codeCmd = 'D:\Microsoft VS Code\bin\code.cmd'
$buildRoot = Join-Path $projectRoot 'build'

if (!(Test-Path -LiteralPath $vivadoBat)) { throw "Vivado not found: $vivadoBat" }
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$temporaryRoot = Join-Path $buildRoot 'tmp'
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
# Override only this script process and its children, not the Windows user profile.
$env:TEMP = $temporaryRoot
$env:TMP = $temporaryRoot

if ($Action -eq 'doctor') {
    & $vivadoBat -version
    if ($LASTEXITCODE -ne 0) { throw 'Vivado version check failed' }
    if (Test-Path -LiteralPath $codeCmd) {
        & $codeCmd --version
        if ($LASTEXITCODE -ne 0) { throw 'VS Code version check failed' }
    }
    Write-Output "RTL: $projectRoot\rtl"
    Write-Output "Reference: $referenceRoot"
    Write-Output 'No FPGA board or pin constraints selected.'
    exit 0
}

if ($Action -eq 'definitions-check') {
    & (Join-Path $PSScriptRoot 'check_definitions.ps1')
    exit 0
}

if ($Action -eq 'reference-check') {
    $checkRoot = Join-Path $buildRoot 'reference-check'
    New-Item -ItemType Directory -Path $checkRoot -Force | Out-Null
    $pkgRoot = Join-Path $referenceRoot 'vpackage'
    $packageFiles = @('config_pkg.sv','structure_pkg.sv','ctrl_pkg.sv',
        'rat_pkg.sv','retire_pkg.sv','rob_pkg.sv','issue_pkg.sv') |
        ForEach-Object { Join-Path $pkgRoot $_ }
    $sourceFiles = foreach ($dir in @('core','utils','lockstep')) {
        Get-ChildItem -LiteralPath (Join-Path $referenceRoot "vsrc\$dir") -File |
            Where-Object { $_.Extension -in @('.v','.sv') } |
            Sort-Object Name | Select-Object -ExpandProperty FullName
    }
    Push-Location $checkRoot
    try {
        & (Join-Path $vivadoRoot 'bin\xvlog.bat') --sv --work xil_defaultlib @packageFiles @sourceFiles
        if ($LASTEXITCODE -ne 0) { throw "Reference compile failed; see $checkRoot\xvlog.log" }
        & (Join-Path $vivadoRoot 'bin\xelab.bat') xil_defaultlib.core_cpu -s reference_core -debug typical
        if ($LASTEXITCODE -ne 0) { throw "Reference elaboration failed; see $checkRoot\xelab.log" }
        Write-Output 'REFERENCE_ELABORATION_PASS (not a functional CPU test)'
    } finally { Pop-Location }
    exit 0
}

if ($Action -eq 'open-vivado') {
    $projectFile = Join-Path $buildRoot 'vivado\mysuperscaler.xpr'
    if (!(Test-Path -LiteralPath $projectFile)) {
        & $PSCommandPath -Action project
        if ($LASTEXITCODE -ne 0) { throw 'Project creation failed' }
    }
    # The user requested an interactive IDE; start this GUI visibly.
    Start-Process -FilePath $vivadoBat -ArgumentList @('-mode','gui', $projectFile) -WorkingDirectory $projectRoot
    exit 0
}

$scriptNames = @{ project='create_project.tcl'; sim='run_sim.tcl'; synth='run_synth.tcl' }
$scriptPath = Join-Path $PSScriptRoot $scriptNames[$Action]
$logPath = Join-Path $buildRoot "vivado_$Action.log"
$journalPath = Join-Path $buildRoot "vivado_$Action.jou"
Push-Location $projectRoot
try {
    & $vivadoBat -mode batch -source $scriptPath -log $logPath -journal $journalPath
    if ($LASTEXITCODE -ne 0) { throw "Vivado $Action failed. See $logPath" }
} finally { Pop-Location }
