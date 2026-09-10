[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CommandPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [switch]$CeVIOIsFree
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $CeVIOIsFree) { throw 'CeVIO availability confirmation required.' }
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) { throw 'Requires Windows PowerShell x64.' }
$command = Get-Content -LiteralPath $CommandPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($command.Id -cnotmatch '^[0-9a-f]{32}$' -or $command.Text -isnot [string] -or
    [string]::IsNullOrWhiteSpace($command.Text) -or $command.Text.Length -gt 280) { throw 'Invalid speech command.' }
$id = [string]$command.Id
$wave = Join-Path $OutputDirectory ($id + '.wav')
if (Test-Path -LiteralPath $wave) { throw 'Output already exists; not retrying an ambiguous command.' }
$timer = [Diagnostics.Stopwatch]::StartNew()
$dll = Join-Path $env:ProgramFiles 'CeVIO\CeVIO Creative Studio (64bit)\CeVIO.Talk.RemoteService.DLL'
Add-Type -Path $dll
$result = [CeVIO.Talk.RemoteService.ServiceControl]::StartHost($false)
if ([int]$result -ne 0) { throw 'CeVIO StartHost failed.' }
$cast = -join ([char[]]@(0x3055,0x3068,0x3046,0x3055,0x3055,0x3089))
if (@([CeVIO.Talk.RemoteService.Talker]::AvailableCasts) -notcontains $cast) { throw 'Sasara is unavailable.' }
$talker = New-Object -TypeName CeVIO.Talk.RemoteService.Talker -ArgumentList $cast
$talker.Volume=50; $talker.Speed=50; $talker.Tone=50; $talker.Alpha=50; $talker.ToneScale=50
$phonemeStart = $timer.ElapsedMilliseconds
$phonemes = @($talker.GetPhonemes([string]$command.Text))
$phonemeMs = $timer.ElapsedMilliseconds - $phonemeStart
if ($phonemes.Count -eq 0) { throw 'No phonemes returned.' }
foreach ($p in $phonemes) {
    if ($p.StartTime -lt 0 -or $p.EndTime -lt $p.StartTime) { throw 'Invalid phoneme interval.' }
}
$synthStart = $timer.ElapsedMilliseconds
if (-not $talker.OutputWaveToFile([string]$command.Text, $wave)) { throw 'Synthesis failed.' }
$synthMs = $timer.ElapsedMilliseconds - $synthStart
if (-not (Test-Path -LiteralPath $wave) -or (Get-Item -LiteralPath $wave).Length -le 44) { throw 'Missing or empty WAV.' }
# Mouth synchronization uses this WAV's amplitude and the playback device cursor.
# Phonemes are checked but are not used for phonetic mouth shapes in this probe.
[ordered]@{ Id=$id; Stage='synthesized'; PhonemeMs=$phonemeMs; SynthesisMs=$synthMs; WorkerMs=$timer.ElapsedMilliseconds; SynthesizedUtc=[DateTime]::UtcNow.ToString('o') } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory ($id+'.synthesis.json')) -Encoding UTF8
# Process exit releases this worker; never close or restart the CeVIO host.
