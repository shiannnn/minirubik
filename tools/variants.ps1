# Writes the assembly variants of stage5.s. Ripes 2.2.6 has no .if or .macro, so
# the assemble-time switch is this filter: lines of the form #ifdef NAME, #else
# and #endif in column 0 select code, everything else is copied unchanged.
#   powershell -File tools\variants.ps1                 stage5_cli.s, stage5_led.s
#   powershell -File tools\variants.ps1 -Dump <dir>     also <dir>\stage5_dump.s
# cli   no defines: no renderer, assembles under --mode cli, used for --iret
# led   LED: the GUI build, drives LED_MATRIX_0_BASE
# dump  LED and DUMP: same renderer, frame buffer in memory and printed, so the
#       renderer can be checked without the GUI (tools\verify_led.ps1)
param([string]$Dump)
$ErrorActionPreference = 'Stop'
function Build([string[]]$Defs, [string]$Out, [string]$Title) {
    $stack = New-Object System.Collections.ArrayList   # one bool per open #ifdef
    $lines = foreach ($l in (Get-Content -LiteralPath 'stage5.s')) {
        if ($l -match '^#ifdef (\w+)\s*$') { [void]$stack.Add(($Defs -contains $Matches[1])); continue }
        if ($l -match '^#else\s*$') { $stack[$stack.Count - 1] = -not $stack[$stack.Count - 1]; continue }
        if ($l -match '^#endif\s*$') { $stack.RemoveAt($stack.Count - 1); continue }
        if ($stack -notcontains $false) { $l }
    }
    if ($stack.Count) { throw 'unbalanced #ifdef in stage5.s' }
    $head = "# GENERATED from stage5.s by tools\variants.ps1, $Title. Do not edit."
    [System.IO.File]::WriteAllText([System.IO.Path]::Combine((Get-Location).Path, $Out), ([string]::Join("`n", (@($head) + @($lines))) + "`n"))
}
Build @() 'stage5_cli.s' 'CLI build, no renderer'
Build @('LED') 'stage5_led.s' 'GUI build, LED matrix renderer'
if ($Dump) {
    New-Item -ItemType Directory -Force $Dump | Out-Null
    Build @('LED', 'DUMP') (Join-Path $Dump 'stage5_dump.s') 'test build, frame buffer printed'
}
