$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$referenceRoot = 'D:\zz\superscalercore\vpackage'
$headerRoot = Join-Path $projectRoot 'vpackage'
$macros = @{}
foreach ($file in (Get-ChildItem -LiteralPath $headerRoot -Filter '*.vh' -File)) {
    $text = [IO.File]::ReadAllText($file.FullName)
    foreach ($m in [regex]::Matches($text, '(?m)^`define[ \t]+(\w+)[ \t]+([^\r\n]+)$')) {
        $name = $m.Groups[1].Value
        if ($macros.ContainsKey($name)) { throw "Duplicate macro: $name" }
        $macros[$name] = $m.Groups[2].Value.Trim()
    }
}

function Get-PlainSource([string]$path) {
    $text = [IO.File]::ReadAllText($path)
    $text = [regex]::Replace($text, '/\*[\s\S]*?\*/', '')
    return [regex]::Replace($text, '//[^\r\n]*', '')
}

function Resolve-Constant([string]$name, [hashtable]$definitions, [hashtable]$cache) {
    if ($cache.ContainsKey($name)) { return $cache[$name] }
    if (!$definitions.ContainsKey($name)) { throw "Unknown definition: $name" }
    $expression = $definitions[$name].Replace([string][char]96, '')
    $expression = [regex]::Replace($expression, "[0-9]+\s*'\s*([hHdDbBoO])\s*([0-9a-fA-F_]+)", {
        param($literal)
        $radix = @{ h=16; d=10; b=2; o=8 }[$literal.Groups[1].Value.ToLower()]
        return [string][Convert]::ToInt64($literal.Groups[2].Value.Replace('_',''), $radix)
    })
    $expression = [regex]::Replace($expression, '\b[A-Za-z_][A-Za-z0-9_]*\b', {
        param($symbol)
        return [string](Resolve-Constant $symbol.Value $definitions $cache)
    })
    $expression = [regex]::Replace($expression, '(\d+)\s*<<\s*(\d+)', {
        param($shift)
        return [string]([long]$shift.Groups[1].Value -shl [int]$shift.Groups[2].Value)
    })
    if ($expression -notmatch '^[\d\s()+*/-]+$') {
        throw "Unsupported constant expression: $name = $expression"
    }
    $table = New-Object System.Data.DataTable
    $value = [long]$table.Compute($expression, '')
    $cache[$name] = $value
    return $value
}

$reference = @{}
$expected = @{}
$statePrefixes = @{ 'ctrl_pkg.sv'='CTRL'; 'rob_pkg.sv'='ROB'; 'rat_pkg.sv'='RAT';
    'retire_pkg.sv'='RT'; 'issue_pkg.sv'='ISSUE' }
foreach ($file in (Get-ChildItem -LiteralPath $referenceRoot -Filter '*.sv' -File)) {
    $text = Get-PlainSource $file.FullName
    foreach ($m in [regex]::Matches($text, '\blocalparam\s+(?:int\s+)?(\w+)\s*=\s*([^;]+);')) {
        $name = $m.Groups[1].Value
        $reference[$name] = $m.Groups[2].Value.Trim()
        $expected[$name] = $name
    }
    foreach ($enum in [regex]::Matches($text, 'typedef\s+enum[^{}]*\{([^}]+)\}')) {
        foreach ($m in [regex]::Matches($enum.Groups[1].Value, '(\w+)\s*=\s*([^,]+)')) {
            $name = $m.Groups[1].Value
            $macroName = $name
            if ($statePrefixes.ContainsKey($file.Name) -and
                $name -in @('NORMAL','RESTORE','STALL','CLEAR','ERROR','EXCEPT',
                    'LOCKSTEP_CLEAR','LOCKSTEP_RESTORE','EXCECPT_HANDLE')) {
                $macroName = $statePrefixes[$file.Name] + '_' + $name
            }
            $reference[$macroName] = $m.Groups[2].Value.Trim()
            $expected[$macroName] = $macroName
        }
    }
}

$referenceCache = @{}
$macroCache = @{}
$checks = 0
foreach ($name in ($expected.Keys | Sort-Object)) {
    $referenceValue = Resolve-Constant $name $reference $referenceCache
    $macroValue = Resolve-Constant $name $macros $macroCache
    if ($referenceValue -ne $macroValue) {
        throw "Mismatch: $name upstream=$referenceValue header=$macroValue"
    }
    $checks++
}

$typePrefixes = @{ rs_payload_ram='RS_PAYLOAD_RAM'; rob_entry_t='ROB_ENTRY';
    rs_control_t='RS_CONTROL'; rs_entry_t='RS_ENTRY' }
$typeWidths = @{}
$config = Get-PlainSource (Join-Path $referenceRoot 'config_pkg.sv')
$fieldChecks = 0
foreach ($record in [regex]::Matches($config,
    'typedef\s+struct\s+packed\s*\{([^}]+)\}\s*(\w+)\s*;')) {
    $typeName = $record.Groups[2].Value
    $prefix = $typePrefixes[$typeName]
    $fields = @()
    foreach ($field in [regex]::Matches($record.Groups[1].Value,
        '(\w+)\s*(?:\[([^\]]+)\]\s*|\s+)(\w+)\s*;')) {
        if ($field.Groups[1].Value -eq 'logic') {
            if ($field.Groups[2].Success) {
                $range = $field.Groups[2].Value.Split(':')
                $reference['__FIELD_UPPER'] = $range[0]
                $reference['__FIELD_LOWER'] = $range[1]
                $referenceCache.Remove('__FIELD_UPPER')
                $referenceCache.Remove('__FIELD_LOWER')
                $width = (Resolve-Constant '__FIELD_UPPER' $reference $referenceCache) -
                    (Resolve-Constant '__FIELD_LOWER' $reference $referenceCache) + 1
            } else { $width = 1 }
        } else {
            $width = $typeWidths[$field.Groups[1].Value]
            if (!$width) { throw "Unknown packed field type $($field.Groups[1].Value)" }
        }
        $fields += [pscustomobject]@{Name=$field.Groups[3].Value.ToUpper();Width=[long]$width}
    }
    $offset = 0
    for ($i=$fields.Count-1; $i -ge 0; $i--) {
        $fieldPrefix = $prefix + '_' + $fields[$i].Name
        $lsb = Resolve-Constant ($fieldPrefix+'_LSB') $macros $macroCache
        $msb = Resolve-Constant ($fieldPrefix+'_MSB') $macros $macroCache
        if ($lsb -ne $offset -or $msb -ne ($offset+$fields[$i].Width-1)) {
            throw "Packed field mismatch: $fieldPrefix actual=[$msb`:$lsb] expected=[$($offset+$fields[$i].Width-1)`:$offset]"
        }
        $offset += $fields[$i].Width
        $fieldChecks++
    }
    $typeWidths[$typeName] = $offset
    if ((Resolve-Constant ($prefix+'_WIDTH') $macros $macroCache) -ne $offset) {
        throw "Packed width mismatch: $typeName"
    }
    Write-Output "$typeName width=$offset"
}
Write-Output "DEFINITIONS_CHECK_PASS constants=$checks packed_fields=$fieldChecks"
