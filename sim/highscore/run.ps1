$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$modelsim = 'C:\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
$work = Join-Path $PSScriptRoot 'work'

if (Test-Path $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
}

& (Join-Path $modelsim 'vlib.exe') $work
& (Join-Path $modelsim 'vlog.exe') -sv -work $work '+define+SIMULATION' `
    (Join-Path $repo 'rtl\modules\jtframe\hdl\ram\jtframe_dual_ram.v') `
    (Join-Path $repo 'rtl\dogyuun\dogyuun_highscore.sv') `
    (Join-Path $repo 'sim\highscore\DogyuunHighScoreManager_tb.sv')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $modelsim 'vsim.exe') -c -lib $work `
    DogyuunHighScoreManager_tb -do 'run -all; quit -f'
exit $LASTEXITCODE
