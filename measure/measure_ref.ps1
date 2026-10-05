# Measure the GCC reference (ref/stage3_ref.c, riscv64-unknown-elf-gcc -O2
# -march=rv32i -mabi=ilp32) with Ripes --iret on the same states as
# measure_stage4.ps1. Two builds per state: plain C as in stage3.c, and
# -DQUICK, which uses the same h == 0 test as stage3.s.
# The compiler runs inside WSL; Ripes runs on Windows.
#   powershell -File measure\measure_ref.ps1 -Ripes <path\to\Ripes.exe>
param(
    [Parameter(Mandatory = $true)][string]$Ripes,
    [string]$Proc = 'RV32_ISS',
    [string]$Out = 'measure\ref_results.csv'
)
$ErrorActionPreference = 'Stop'
$states = '12345671111111', '23475162132323', '21345671111111', '12347651111111',
          '61352472313211', '62345713133111', '24316572122213', '25713642221111',
          '24513763133333', '43752611332133', '25416373331111'
$repo = (Get-Location).Path
$wrepo = (wsl wslpath -a $repo.Replace('\','/'))
$tmp = Join-Path $env:TEMP 'stage4_ref'
New-Item -ItemType Directory -Force $tmp | Out-Null
$wtmp = (wsl wslpath -a $tmp.Replace('\','/'))
$rows = foreach ($s in $states) {
    foreach ($v in @(@('plain', ''), @('quick', '-DQUICK'))) {
        $elf = "$wtmp/$s-$($v[0]).elf"
        wsl bash -c "cd '$wrepo' && sh measure/build_ref.sh $s '$elf' $($v[1])"
        $o = & $Ripes --mode cli --src "$tmp\$s-$($v[0]).elf" -t elf --proc $Proc --iret --timeout 600000 2>&1 | Out-String
        $code = if ($o -match 'exited with code: (-?\d+)') { [int]$Matches[1] } else { -1 }
        $iret = if ($o -match 'instructions retired\s+(\d+)') { [int64]$Matches[1] } else { -1 }
        [pscustomobject]@{ state = $s; build = $v[0]; exit_code = $code; iret = $iret }
    }
}
$rows | Export-Csv -NoTypeInformation -Encoding ascii $Out
$rows | Format-Table -AutoSize
