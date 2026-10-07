<#
  measure.ps1 - Stage 1 measurements for Assignment 1 (Ripes CLI).

  Usage (PowerShell 5.1):
    .\measure.ps1 -Ripes "C:\path\Ripes.exe" -Test ratio
    .\measure.ps1 -Ripes "C:\path\Ripes.exe" -Test rate -Procs RV32_ISS,<pipelined-id>

  Defaults were checked against the Ripes build at D:\Ripes\Ripes.exe. Its --proc list is
  RV32_SS, RV32_5S_NO_FW_HZ, RV32_5S_NO_HZ, RV32_5S_NO_FW, RV32_5S, RV32_6S_DUAL (no RV32_ISS
  in this build's CLI). Report format: "===== instructions retired" followed by the count.
  Placeholders: {SRC} = assembly file, {PROC} = processor id.
#>
param(
    [Parameter(Mandatory)][string]$Ripes,
    [Parameter(Mandatory)][ValidateSet('ratio','rate')][string]$Test,
    [string[]]$Procs = @('RV32_ISS'),
    [int[]]$SizesMiB = @(0,1,2,4,8),          # ratio test: guest bytes written
    [int[]]$Iters    = @(2000000,10000000),   # rate test: loop iterations
    [int]$Repeats = 3,
    [string]$RipesArgsTemplate = '--mode cli --src {SRC} -t asm --proc {PROC} --iret --cycles',
    [string]$IretRegex = '(?is)instructions retired\s*(\d+)'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$work = Join-Path $here 'work'
New-Item -ItemType Directory -Force $work | Out-Null

function Make-Source($template, $token, $value, $name) {
    $text = (Get-Content (Join-Path $here $template) -Raw).Replace($token, [string]$value)
    $path = Join-Path $work $name
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
    $path
}

# Runs Ripes once; returns peak host working set (bytes), wall seconds, stdout text.
function Run-Ripes($src, $proc) {
    $argStr = $RipesArgsTemplate.Replace('{SRC}', "`"$src`"").Replace('{PROC}', $proc)
    $out = Join-Path $work 'stdout.txt'
    $sw  = [Diagnostics.Stopwatch]::StartNew()
    $p   = Start-Process -FilePath $Ripes -ArgumentList $argStr -PassThru -NoNewWindow `
                         -RedirectStandardOutput $out
    $peak = 0
    while (-not $p.HasExited) {
        try { $p.Refresh(); if ($p.PeakWorkingSet64 -gt $peak) { $peak = $p.PeakWorkingSet64 } } catch {}
        Start-Sleep -Milliseconds 20
    }
    $sw.Stop()
    [pscustomobject]@{ Peak = $peak; Seconds = $sw.Elapsed.TotalSeconds; Text = (Get-Content $out -Raw) }
}

function Get-Iret($text) {
    if ($text -match $IretRegex) { [int64]$Matches[1] } else { $null }
}

if ($Test -eq 'ratio') {
    $proc = $Procs[0]
    $rows = foreach ($mib in $SizesMiB) {
        $n   = [int64]$mib * 1MB
        $src = Make-Source 'memfill.s' '@N@' $n "memfill_$mib.s"
        for ($i = 1; $i -le $Repeats; $i++) {
            $r = Run-Ripes $src $proc
            [pscustomobject]@{ MiB = $mib; Bytes = $n; Run = $i; PeakBytes = $r.Peak; Seconds = [math]::Round($r.Seconds,2) }
        }
    }
    $rows | Format-Table -AutoSize
    $base = ($rows | Where-Object MiB -eq 0 | Measure-Object PeakBytes -Average).Average
    "Baseline (N=0) peak working set: {0:N0} B" -f $base
    foreach ($g in ($rows | Where-Object MiB -gt 0 | Group-Object MiB)) {
        $avg = ($g.Group | Measure-Object PeakBytes -Average).Average
        $n   = $g.Group[0].Bytes
        "N = {0,2} MiB : peak {1,14:N0} B   ratio (peak-baseline)/N = {2:N1} host B per guest B" -f `
            $g.Name, $avg, (($avg - $base) / $n)
    }
    $rows | Export-Csv (Join-Path $here 'ratio_results.csv') -NoTypeInformation
}
else {
    $rows = foreach ($proc in $Procs) {
        foreach ($it in $Iters) {
            $src = Make-Source 'spin.s' '@ITER@' $it "spin_$it.s"
            for ($i = 1; $i -le $Repeats; $i++) {
                $r = Run-Ripes $src $proc
                $iret = Get-Iret $r.Text
                if ($null -eq $iret) { Write-Warning "Could not parse --iret from output; fix `$IretRegex. Raw output:`n$($r.Text)" }
                [pscustomobject]@{ Proc = $proc; Iter = $it; Run = $i; Iret = $iret; Seconds = $r.Seconds }
            }
        }
    }
    $rows | Format-Table -AutoSize
    foreach ($proc in $Procs) {
        $g  = $rows | Where-Object Proc -eq $proc
        $lo = $g | Where-Object Iter -eq ($Iters | Measure-Object -Minimum).Minimum
        $hi = $g | Where-Object Iter -eq ($Iters | Measure-Object -Maximum).Maximum
        $i1 = ($lo | Measure-Object Iret -Average).Average; $t1 = ($lo | Measure-Object Seconds -Average).Average
        $i2 = ($hi | Measure-Object Iret -Average).Average; $t2 = ($hi | Measure-Object Seconds -Average).Average
        if ($t2 -gt $t1 -and $i1 -and $i2) {
            "{0}: slope rate = {1:N0} instr/s  (startup ~ {2:N2} s)" -f $proc, (($i2 - $i1) / ($t2 - $t1)), ($t1 - $i1 / (($i2 - $i1) / ($t2 - $t1)))
        } else { "{0}: not enough valid data to compute a rate" -f $proc }
    }
    # one CSV per processor model, so a later run for another model never overwrites it
    foreach ($proc in $Procs) {
        $rows | Where-Object Proc -eq $proc |
            Export-Csv (Join-Path $here "rate_$proc.csv") -NoTypeInformation
    }
}
