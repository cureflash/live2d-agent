[CmdletBinding()]
param([switch]$WaitForNotification)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$base = Join-Path $env:LOCALAPPDATA 'live2d-agent'
$state = Get-Content -LiteralPath (Join-Path $base 'sync-build.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$runtime = [IO.Path]::GetFullPath([string]$state.WorkingDirectory)
if (-not $runtime.StartsWith($base + '\sync-runtime-', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected runtime.' }
$sessionId = [guid]::NewGuid().ToString('N')
$session = Join-Path $base ('sync-session-' + $sessionId)
$null = New-Item -ItemType Directory -Path $session
$sessionPointer = Join-Path $base 'sync-session.json'
# A test session is explicit and one-shot; this is not a production pause policy.
$lockPath = Join-Path $base 'sync-probe.lock'
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    Write-Host 'One speech synchronization test. Keep CeVIO free of other work until it finishes.'
    $answer = Read-Host 'Type FREE if CeVIO is available now; Enter cancels'
    if ($answer -cne 'FREE') { Write-Host 'Cancelled; CeVIO was not accessed.'; return }
    # Start a dedicated instance with a private copy, avoiding an old instance
    # consuming the same ready file or sharing its audio ownership.
    $instance = Join-Path $session 'runtime'
    Copy-Item -LiteralPath $runtime -Destination $instance -Recurse
    $speechDir = Join-Path $instance 'speech'
    Get-ChildItem -LiteralPath $speechDir -File | Remove-Item -Force
    Remove-Item -LiteralPath (Join-Path $instance 'speech.ready') -ErrorAction SilentlyContinue
    $preview = Start-Process -FilePath (Join-Path $instance 'Demo.exe') -WorkingDirectory $instance -PassThru -RedirectStandardOutput (Join-Path $session 'render.log') -RedirectStandardError (Join-Path $session 'render-error.log')
    $startup = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Milliseconds 250
        $preview.Refresh()
        if ($preview.HasExited) { throw 'Renderer exited before readiness.' }
        if ($startup.Elapsed.TotalSeconds -gt 60) { throw 'Renderer window readiness timeout.' }
    } until ($preview.MainWindowHandle -ne 0 -and $preview.Responding)
    $startup.Stop()
    $commandPath = Join-Path $session 'command.json'
    if ($WaitForNotification) {
        $self = Get-Process -Id $PID
        [ordered]@{ SessionId=$sessionId; ReceiverPid=$PID; ReceiverStartUtc=$self.StartTime.ToUniversalTime().ToString('o'); Directory=$session } |
            ConvertTo-Json | Set-Content -LiteralPath $sessionPointer -Encoding UTF8
        Write-Host 'WAITING_FOR_NOTIFICATION. Leave this PowerShell and model window open.'
        while (-not (Test-Path -LiteralPath $commandPath)) {
            Start-Sleep -Milliseconds 200
            $preview.Refresh()
            if ($preview.HasExited) { throw 'Renderer closed while waiting.' }
        }
    } else {
        $sentence = -join ([char[]]@(0x58f0,0x306b,0x5408,0x308f,0x305b,0x3066,0x3001,0x53e3,0x304c,0x52d5,0x304f,0x304b,0x78ba,0x8a8d,0x3057,0x3066,0x3044,0x308b,0x3088,0x3002))
        [ordered]@{ Id=[guid]::NewGuid().ToString('N'); Text=$sentence; SessionId=$sessionId; Source='local-test'; SentUtc=[DateTime]::UtcNow.ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath $commandPath -Encoding UTF8
    }
    $command = Get-Content -LiteralPath $commandPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($command.SessionId -cne $sessionId -or $command.Id -cnotmatch '^[0-9a-f]{32}$') { throw 'Wrong session or invalid command ID.' }
    $id = [string]$command.Id
    $receivedUtc = [DateTime]::UtcNow.ToString('o')
    $workerStart = [Diagnostics.Stopwatch]::StartNew()
    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -File (Join-Path $PSScriptRoot 'Synthesize-AgentSpeech.ps1') -CommandPath $commandPath -OutputDirectory $speechDir -CeVIOIsFree
    if ($LASTEXITCODE -ne 0) { throw 'Synthesis worker failed; no playback requested.' }
    $workerStart.Stop()
    $ready = Join-Path $instance 'speech.ready'
    [IO.File]::WriteAllText(($ready+'.tmp'),$id,[Text.Encoding]::ASCII)
    [IO.File]::Move(($ready+'.tmp'),$ready)
    $playbackWait = [Diagnostics.Stopwatch]::StartNew()
    $statusPath = Join-Path $speechDir ($id+'.status')
    do {
        Start-Sleep -Milliseconds 100
        $preview.Refresh()
        if ($preview.HasExited) { throw 'Renderer exited during speech.' }
        if ($playbackWait.Elapsed.TotalSeconds -gt 120) { throw 'Playback did not complete; inspect local status.' }
        $events = if (Test-Path -LiteralPath $statusPath) { [IO.File]::ReadAllText($statusPath) } else { '' }
        if ($events -match '(failed|missing|unsupported|timeout|regressed|interrupted|wave_size|wave_header|wave_chunk|riff_size|wave_format|duplicate_data|wave_padding)') { throw 'Native playback failed; inspect local status.' }
    } until ($events.Contains('playback_completed'))
    [ordered]@{ Kind='single_command_sync_probe'; Id=$id; Source=$command.Source; SentUtc=$command.SentUtc; ReceivedUtc=$receivedUtc; WindowReadyMs=$startup.ElapsedMilliseconds; WorkerProcessMs=$workerStart.ElapsedMilliseconds; PlaybackCompletedUtc=[DateTime]::UtcNow.ToString('o'); ActualAudioOnsetMs=$null; AudiblePlayback='requires_user_confirmation'; VisualLipSync='requires_user_confirmation' } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $session 'result.json') -Encoding UTF8
    Write-Host 'PLAYBACK_COMPLETED. Please check audible speech and mouth movement; close the model when finished.'
    $preview.WaitForExit()
} finally {
    if (Test-Path -LiteralPath $sessionPointer) {
        $pointer = Get-Content -LiteralPath $sessionPointer -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($pointer.SessionId -ceq $sessionId) { Remove-Item -LiteralPath $sessionPointer }
    }
    $lock.Dispose()
    # No forced window termination, host close, or retry after ambiguous failure.
}
