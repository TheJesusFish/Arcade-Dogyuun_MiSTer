$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$modelsim = 'C:\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
$work = Join-Path $PSScriptRoot 'work'

if (Test-Path $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
}

& (Join-Path $modelsim 'vlib.exe') $work
& (Join-Path $modelsim 'vlog.exe') -sv -work $work `
    (Join-Path $repo 'sim\pause\DogyuunPauseAudio_tb.sv') `
    (Join-Path $repo 'rtl\dogyuun\dogyuun_sound_mixer.sv') `
    (Join-Path $repo 'rtl\dogyuun\dogyuun_sound.sv')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $modelsim 'vsim.exe') -c -lib $work `
    DogyuunPauseAudio_tb -do 'run -all; quit -f'
exit $LASTEXITCODE
