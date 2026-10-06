# Checks the LED renderer of stage5.s without the Ripes GUI.
# Builds the DUMP variant, whose frame buffer is plain memory that is printed
# after every redraw, runs it in Ripes CLI for a list of states, and compares
# every frame with tools\led_ref.c, which rotates 24 stickers in 3-D.
#   powershell -File tools\verify_led.ps1 -Ripes <path\to\Ripes.exe> [-Cc gcc]
param(
    [Parameter(Mandatory = $true)][string]$Ripes,
    [string]$Cc = 'gcc',
    [string]$Work = (Join-Path $env:TEMP 'minirubik_led')
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Work | Out-Null
& $Cc -O1 -std=c99 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -o (Join-Path $Work 'led_ref.exe') tools\led_ref.c
if ($LASTEXITCODE) { throw 'cannot build tools\led_ref.c' }
& powershell -NoProfile -File tools\variants.ps1 -Dump $Work
$states = '12345671111111', '23475162132323', '21345671111111', '12347651111111', '61352472313211',
    '62345713133111', '24316572122213', '24513763133333', '25416373331111'
$log = Join-Path $Work 'frames.txt'
Remove-Item -ErrorAction SilentlyContinue $log
foreach ($s in $states) {
    $reg = 'gpr:10=' + $s.Substring(0, 7) + ',11=' + $s.Substring(7)
    $o = & $Ripes --mode cli --src (Join-Path $Work 'stage5_dump.s') -t asm --proc RV32_ISS --reginit $reg --timeout 600000 2>&1 | Out-String
    Add-Content -Encoding ascii $log ($o -replace "`0", '')
}
& (Join-Path $Work 'led_ref.exe') check $log
exit $LASTEXITCODE
