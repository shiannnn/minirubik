# Run every distance-11 state (measure\all_d11_states.txt, 2,644 lines) through
# stage3.s on Ripes RV32_ISS with --iret, using parallel worker processes, and
# merge the result into measure\all_d11_iret.csv (state, moves, iret).
#   powershell -File measure\measure_all_d11.ps1 -Ripes <path\to\Ripes.exe> [-Workers 6]
# A state counts as correct when the program prints [PASS] with 11 moves; the
# program itself has already replayed the path on the full cube model.
param(
    [Parameter(Mandatory = $true)][string]$Ripes,
    [int]$Workers = 6,
    [string]$Src = 'stage3.s',
    [string]$List = 'measure\all_d11_states.txt',
    [string]$Out = 'measure\all_d11_iret.csv'
)
$ErrorActionPreference = 'Stop'
$Src = (Resolve-Path $Src).Path
$List = (Resolve-Path $List).Path
$tmp = Join-Path $env:TEMP 'stage4_all_d11'
New-Item -ItemType Directory -Force $tmp | Out-Null

$worker = {
    param($Ripes, $Src, $List, $Out, [int]$Part, [int]$Parts)
    $s = Get-Content $List
    $rows = for ($i = $Part; $i -lt $s.Count; $i += $Parts) {
        $st = $s[$i]
        $reg = 'gpr:10=' + $st.Substring(0, 7) + ',11=' + $st.Substring(7)
        $o = & $Ripes --mode cli --src $Src -t asm --proc RV32_ISS --iret --reginit $reg --timeout 600000 2>&1 | Out-String
        # Ripes prints a NUL after every string, hence \x00 in the match
        $mv = if ($o -match '\[PASS\][\s\x00]+\d+[\s\x00]+:[\s\x00]+(\d+)[\s\x00]+moves') { [int]$Matches[1] } else { -1 }
        $it = if ($o -match 'instructions retired\s+(\d+)') { [int64]$Matches[1] } else { -1 }
        [pscustomobject]@{ state = $st; moves = $mv; iret = $it }
    }
    $rows | Export-Csv -NoTypeInformation -Encoding ascii $Out
}
$workerFile = Join-Path $tmp 'worker.ps1'
Set-Content -Encoding ascii $workerFile ('param($Ripes,$Src,$List,$Out,[int]$Part,[int]$Parts)' + "`n" + $worker.ToString().Substring($worker.ToString().IndexOf('$s = Get-Content')))

# paths contain spaces, so every argument is quoted
$procs = 0..($Workers - 1) | ForEach-Object {
    Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-File',
        "`"$workerFile`"", "`"$Ripes`"", "`"$Src`"", "`"$List`"", "`"$tmp\part$_.csv`"", $_, $Workers
}
$procs | Wait-Process
$all = 0..($Workers - 1) | ForEach-Object { Import-Csv "$tmp\part$_.csv" } | Sort-Object state
$all | Export-Csv -NoTypeInformation -Encoding ascii $Out
$it = $all | ForEach-Object { [int64]$_.iret }
$m = $it | Measure-Object -Minimum -Maximum -Average
'states: {0}, wrong length: {1}' -f $all.Count, @($all | Where-Object { $_.moves -ne 11 }).Count
'iret min {0}, mean {1:N0}, max {2}, over 5e7: {3}' -f $m.Minimum, $m.Average, $m.Maximum, @($it | Where-Object { $_ -gt 50000000 }).Count
