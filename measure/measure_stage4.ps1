# Measure stage3.s with Ripes --iret, one state per run, through the same CLI
# interface a user has: the state is passed with --reginit, so every number is
# the retired-instruction count of a complete program: start-up, input decode,
# parse, search, replay check, printing and exit.
#   powershell -File measure\measure_stage4.ps1 -Ripes <path\to\Ripes.exe> [-Worst]
# -Worst also runs the 20 distance-11 states with the most host IDA* nodes
# (listed in measure\worst20_d11.csv).
# Output: measure\stage4_results.csv (state, expected, moves, status, iret).
param(
    [Parameter(Mandatory = $true)][string]$Ripes,
    [string]$Proc = 'RV32_ISS',
    [string]$Src = 'stage3.s',
    [string]$Out = 'measure\stage4_results.csv',
    [switch]$Worst
)
$ErrorActionPreference = 'Stop'
# state, expected distance
$cases = @(
    @('12345671111111', 0),     # solved cube
    @('23475162132323', 3),     # short scramble
    @('21345671111111', 11),    # distance-11 vector from the assignment
    @('12347651111111', 11),    # distance-11 state with the most IDA* nodes
    @('61352472313211', 11),    # second most nodes
    @('62345713133111', 8),
    @('24316572122213', 8),
    @('25713642221111', 8),
    @('24513763133333', 9),
    @('43752611332133', 9),
    @('25416373331111', 10)
)
if ($Worst) {
    $known = $cases | ForEach-Object { $_[0] }
    $cases += Import-Csv 'measure\worst20_d11.csv' | Where-Object { $known -notcontains $_.state } |
        ForEach-Object { , @($_.state, 11) }
}
$rows = foreach ($c in $cases) {
    $reg = 'gpr:10=' + $c[0].Substring(0, 7) + ',11=' + $c[0].Substring(7)
    $o = & $Ripes --mode cli --src $Src -t asm --proc $Proc --iret --reginit $reg --timeout 600000 2>&1 | Out-String
    $moves = if ($o -match '\[PASS\][\s\x00]+\d+[\s\x00]+:[\s\x00]+(\d+)[\s\x00]+moves') { [int]$Matches[1] } else { -1 }
    $status = if ($moves -eq $c[1]) { 'PASS' } else { 'FAIL' }
    $iret = if ($o -match 'instructions retired\s+(\d+)') { [int64]$Matches[1] } else { -1 }
    [pscustomobject]@{ state = $c[0]; expected = $c[1]; moves = $moves; status = $status; iret = $iret }
}
$rows | Export-Csv -NoTypeInformation -Encoding ascii $Out
$rows | Format-Table -AutoSize
