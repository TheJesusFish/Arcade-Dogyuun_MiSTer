$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$releaseFiles = @(
    'releases\Dogyuun.mra'
    'releases\alternatives\Dogyuun (older set).mra'
    'releases\alternatives\Dogyuun (oldest set).mra'
    'releases\alternatives\Dogyuun (10-9-1992 location test).mra'
)
$expectedNames = @(
    'Shot'
    'Bomb or Speed'
    'Merge or Detach'
    'Start'
    'Coin'
    'Pause'
    '-'
    '-'
    '-'
    'Savestates'
)
$expectedDefaults = @('A', 'B', 'X', 'Start', 'Select', 'R', 'L')

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

foreach ($relativePath in $releaseFiles) {
    $path = Join-Path $repo $relativePath
    [xml]$xml = Get-Content -LiteralPath $path -Raw
    $root = $xml.misterromdescription
    $buttons = $root.buttons
    $names = @(([string]$buttons.names).Split(','))
    $defaults = @(([string]$buttons.default).Split(','))

    Assert-True ($names.Count -eq 10) "Wrong action count in $relativePath"
    Assert-True (($names -join ',') -eq ($expectedNames -join ',')) `
        "Wrong action positions in $relativePath"
    Assert-True (($defaults -join ',') -eq ($expectedDefaults -join ',')) `
        "Wrong compressed defaults in $relativePath"
    Assert-True (([string]$buttons.count) -eq '3') `
        "Game-button count changed in $relativePath"
    Assert-True (([string]$root.rbf) -eq 'Dogyuun') `
        "Wrong RBF target in $relativePath"

    $savestatesRawBit = 4 + [Array]::IndexOf($names, 'Savestates')
    Assert-True ($savestatesRawBit -eq 13) `
        "Savestates does not map to raw joystick bit 13 in $relativePath"
    Assert-True (-not ($defaults -contains '-')) `
        "Default mapping contains a placeholder in $relativePath"
}

$top = Get-Content -LiteralPath (Join-Path $repo 'Arcade-Dogyuun.sv') -Raw
Assert-True ($top -match '\.joySS\s*\(\s*ss_joystick\[13\]\s*\)') `
    'savestate_ui no longer listens on raw joystick bit 13'

$qsf = Get-Content -LiteralPath (Join-Path $repo 'Arcade-Dogyuun.qsf') -Raw
Assert-True ($qsf -match 'JTFRAME_BUTTONS=3') `
    'Dogyuun game-button count is no longer three'

$ui = Get-Content -LiteralPath `
    (Join-Path $repo 'rtl\dogyuun\savestate\savestate_ui.sv') -Raw
Assert-True ($ui -match 'if\s*\(joyDown\s*&\s*~lastDown\)') `
    'Savestates+Down save edge is missing'
Assert-True ($ui -match 'if\s*\(joyUp\s*&\s*~lastUp\)') `
    'Savestates+Up load edge is missing'
Assert-True ($ui -match 'joyRight\s*&\s*~lastRight') `
    'Savestates+Right slot edge is missing'
Assert-True ($ui -match 'joyLeft\s*&\s*~lastLeft') `
    'Savestates+Left slot edge is missing'
Assert-True ($ui -match "'h05: begin ss_save <= pressed & alt; ss_load <= pressed & ~alt") `
    'Keyboard Alt+F1/F1 save/load behavior changed'

Write-Host 'PASS: all 4 release MRAs expose Savestates on raw joystick bit 13.'
Write-Host 'PASS: defaults remain compressed and keyboard/controller actions match IGSPGM.'
