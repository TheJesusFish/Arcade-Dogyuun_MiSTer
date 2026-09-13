$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$hiscoreDat = Join-Path $repo '..\tools\mame\mame0288\plugins\hiscore\hiscore.dat'

$expected = @{
    'dogyuun'  = '00 10 03 4a 00 7c 00 1b'
    'dogyuuna' = '00 10 03 4a 00 7c 00 1b'
    'dogyuunb' = '00 10 03 4a 00 7c 01 1b'
    'dogyuunt' = '00 10 03 4a 00 7c 01 1b'
}

$releaseFiles = @(
    'releases\Dogyuun.mra'
    'releases\alternatives\Dogyuun (older set).mra'
    'releases\alternatives\Dogyuun (oldest set).mra'
    'releases\alternatives\Dogyuun (10-9-1992 location test).mra'
)

function Normalize-Hex([string]$Text) {
    return (($Text -split '\s+' | Where-Object { $_ }) -join ' ').ToLowerInvariant()
}

function Assert-Equal($Actual, $ExpectedValue, [string]$Message) {
    if ($Actual -ne $ExpectedValue) {
        throw "$Message (got '$Actual', expected '$ExpectedValue')"
    }
}

if (-not (Test-Path -LiteralPath $hiscoreDat)) {
    throw "MAME 0.288 hiscore.dat not found: $hiscoreDat"
}

$mameDescriptors = @{}
$currentSets = @()
foreach ($line in Get-Content -LiteralPath $hiscoreDat) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0) {
        $currentSets = @()
    } elseif ($trimmed -match '^([a-z0-9_]+):$') {
        $currentSets += $Matches[1]
    } elseif ($trimmed.StartsWith('@:')) {
        foreach ($set in $currentSets) {
            if ($expected.ContainsKey($set)) {
                $fields = $trimmed.Split(',')
                if (($fields.Count -ne 6) -or
                    ($fields[0] -ne '@:maincpu') -or
                    ($fields[1] -ne 'program')) {
                    throw "Unexpected MAME descriptor syntax for ${set}: $trimmed"
                }
                $start = [Convert]::ToUInt32($fields[2], 16)
                $length = [Convert]::ToUInt16($fields[3], 16)
                $first = [Convert]::ToByte($fields[4], 16)
                $last = [Convert]::ToByte($fields[5], 16)
                $bytes = '{0:x2} {1:x2} {2:x2} {3:x2} {4:x2} {5:x2} {6:x2} {7:x2}' -f `
                    (($start -shr 24) -band 0xff), (($start -shr 16) -band 0xff), `
                    (($start -shr 8) -band 0xff), ($start -band 0xff), `
                    (($length -shr 8) -band 0xff), ($length -band 0xff), `
                    $first, $last
                $mameDescriptors[$set] = $bytes
            }
        }
    }
}

foreach ($set in $expected.Keys) {
    if (-not $mameDescriptors.ContainsKey($set)) {
        throw "MAME hiscore descriptor missing for $set"
    }
    Assert-Equal $mameDescriptors[$set] $expected[$set] `
        "MAME hiscore descriptor changed for $set"
}

$seenSets = @{}
function Test-SupportedMra([string]$RelativePath, [string]$ExpectedRbf) {
    $path = Join-Path $repo $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Supported MRA missing: $relativePath"
    }

    [xml]$xml = Get-Content -LiteralPath $path -Raw
    $root = $xml.misterromdescription
    $set = [string]$root.setname
    if (-not $expected.ContainsKey($set)) {
        throw "Unexpected supported set '$set' in $relativePath"
    }
    if ($seenSets.ContainsKey($set)) {
        throw "Duplicate supported MRA for set '$set'"
    }
    $seenSets[$set] = $true

    Assert-Equal ([string]$root.rbf) $ExpectedRbf `
        "Wrong RBF target in $relativePath"

    $roms = @($root.rom)
    $indices = @($roms | ForEach-Object { [int]$_.index })
    if (($indices | Sort-Object -Unique).Count -ne $indices.Count) {
        throw "Duplicate ROM index in $relativePath"
    }
    Assert-Equal (($indices | Sort-Object) -join ',') '0,1,4' `
        "Unexpected ROM index allocation in $relativePath"

    $descriptorRom = @($roms | Where-Object { [int]$_.index -eq 4 })
    Assert-Equal $descriptorRom.Count 1 `
        "Expected one index-4 descriptor in $relativePath"
    $descriptor = Normalize-Hex ([string]$descriptorRom[0].part)
    Assert-Equal $descriptor $expected[$set] `
        "Wrong high-score descriptor in $relativePath"

    $nvram = @($root.nvram)
    Assert-Equal $nvram.Count 1 "Expected one NVRAM node in $relativePath"
    Assert-Equal ([string]$nvram[0].index) '2' `
        "Wrong NVRAM index in $relativePath"
    Assert-Equal ([string]$nvram[0].size) '264' `
        "Wrong NVRAM size in $relativePath"
}

foreach ($relativePath in $releaseFiles) {
    Test-SupportedMra $relativePath 'Dogyuun'
}

Assert-Equal $seenSets.Count $expected.Count `
    'Release supported set inventory is incomplete'

$allMras = Get-ChildItem -LiteralPath (Join-Path $repo 'releases') `
    -Filter '*.mra' -Recurse -File
foreach ($file in $allMras) {
    [xml]$xml = Get-Content -LiteralPath $file.FullName -Raw
    $set = [string]$xml.misterromdescription.setname
    if (($set -eq 'dogyuunto') -or ($set -eq 'dogyuunbl')) {
        throw "Excluded hardware personality unexpectedly has an MRA: $set"
    }
}

$obsoleteArtifacts = @(
    'releases\candidates'
    'releases\Dogyuun SS Freeze Diagnostic.mra'
    'releases\Dogyuun-SS-Freeze-Diag.rbf'
)
foreach ($relativePath in $obsoleteArtifacts) {
    if (Test-Path -LiteralPath (Join-Path $repo $relativePath)) {
        throw "Obsolete release artifact remains: $relativePath"
    }
}

$releaseRbfs = @(Get-ChildItem -LiteralPath (Join-Path $repo 'releases') `
    -Filter '*.rbf' -Recurse -File)
Assert-Equal $releaseRbfs.Count 1 'Release tree must contain exactly one RBF'
Assert-Equal $releaseRbfs[0].Name 'Dogyuun.rbf' `
    'Unexpected RBF remains in the release tree'

Write-Host 'PASS: 4 promoted release MRAs match MAME 0.288 high-score metadata.'
Write-Host 'PASS: release tree contains one RBF and no candidate/diagnostic artifacts.'
Write-Host 'PASS: dogyuunto and dogyuunbl remain excluded.'
