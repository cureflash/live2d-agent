# Run in a separate 64-bit Windows PowerShell 5.1 process.
# Experimental: not yet verified on Windows. Never closes the CeVIO host.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DllPath,
    [Parameter(Mandatory=$true)][string]$Cast,
    [Parameter(Mandatory=$true)][string]$Text,
    [switch]$CeVIOIsFree
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $CeVIOIsFree) { throw 'Run only when CeVIO is free of other work; specify -CeVIOIsFree.' }
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) {
    throw 'Requires 64-bit Windows PowerShell (Desktop), not PowerShell 7.'
}
if (-not [Environment]::UserInteractive) { throw 'Requires an interactive desktop session.' }
if (-not (Test-Path -LiteralPath $DllPath -PathType Leaf)) { throw 'CeVIO DLL missing.' }
$probeTimer = [Diagnostics.Stopwatch]::StartNew()
$stage = 'LoadAssembly'
$player = $null
try {
    Add-Type -Path $DllPath
    $stage = 'StartHost'
    $hostTimer = [Diagnostics.Stopwatch]::StartNew()
    $startResult = [CeVIO.Talk.RemoteService.ServiceControl]::StartHost($false)
    $hostTimer.Stop()
    if ([int]$startResult -ne 0) { throw "StartHost returned $startResult" }
    $stage = 'SelectCast'
    $casts = @([CeVIO.Talk.RemoteService.Talker]::AvailableCasts)
    if ($casts -notcontains $Cast) { throw 'Requested cast is unavailable.' }
    $talker = New-Object CeVIO.Talk.RemoteService.Talker
    $talker.Cast = $Cast
    $talker.Volume = 50
    $talker.Speed = 50
    $talker.Tone = 50
    $talker.Alpha = 50
    $talker.ToneScale = 50
    # Use one Talker and unchanged settings for phonemes and WAV.
    $stage = 'GetPhonemes'
    $phonemeTimer = [Diagnostics.Stopwatch]::StartNew()
    $phonemes = @($talker.GetPhonemes($Text))
    $phonemeTimer.Stop()
    if ($phonemes.Count -eq 0) { throw 'No phonemes returned.' }
    foreach ($phoneme in $phonemes) {
        if ($phoneme.StartTime -lt 0 -or $phoneme.EndTime -lt $phoneme.StartTime) {
            throw 'Invalid phoneme interval.'
        }
    }
    $wavePath = Join-Path ([IO.Path]::GetTempPath()) ('live2d-agent-probe-' + [guid]::NewGuid().ToString('N') + '.wav')
    $stage = 'SynthesizeWave'
    $synthesisTimer = [Diagnostics.Stopwatch]::StartNew()
    $waveSucceeded = $talker.OutputWaveToFile($Text, $wavePath)
    $synthesisTimer.Stop()
    if (-not $waveSucceeded) { throw 'OutputWaveToFile returned false.' }
    if (-not (Test-Path -LiteralPath $wavePath -PathType Leaf)) { throw 'WAV missing.' }
    if ((Get-Item -LiteralPath $wavePath).Length -le 44) { throw 'WAV empty or too short.' }
    $stage = 'LoadWave'
    $player = New-Object System.Media.SoundPlayer
    $player.SoundLocation = $wavePath
    $player.Load()
    $playCallMs = $probeTimer.ElapsedMilliseconds
    $stage = 'PlayWave'
    $player.PlaySync()
    [pscustomobject]@{
        Kind = 'cevio_standalone_probe_not_integration'
        WaveSynthesisSucceeded = $true
        PlaybackApiReturned = $true
        AudiblePlayback = 'requires_user_confirmation'
        HostStartCallMs = $hostTimer.ElapsedMilliseconds
        PhonemeMs = $phonemeTimer.ElapsedMilliseconds
        SynthesisMs = $synthesisTimer.ElapsedMilliseconds
        ProbeToPlaybackCallMs = $playCallMs
        ActualAudioOnsetMs = $null
        PhonemeCount = $phonemes.Count
        WavePath = $wavePath
        HostClosed = $false
        ConnectionRelease = 'requires_other_app_test_after_process_exit'
    } | ConvertTo-Json
}
catch {
    [Console]::Error.WriteLine(('FAILED at {0}: {1}' -f $stage, $_.Exception.Message))
    exit 1
}
finally {
    if ($null -ne $player) { $player.Dispose() }
}
