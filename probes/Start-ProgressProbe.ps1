[CmdletBinding()]
param([switch]$AutomatedSmoke)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$base = Join-Path $env:LOCALAPPDATA 'live2d-agent'
$state = Get-Content -LiteralPath (Join-Path $base 'sync-build.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$runtime = [IO.Path]::GetFullPath([string]$state.WorkingDirectory)
if (-not $runtime.StartsWith($base + '\sync-runtime-', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected runtime.' }
$sessionId = [guid]::NewGuid().ToString('N')
$session = Join-Path $base ('progress-session-' + $sessionId)
$null = New-Item -ItemType Directory -Path $session
$sessionPointer = Join-Path $base 'progress-session.json'
# A test session is explicit and one-shot; this is not a production pause policy.
$lockPath = Join-Path $base 'sync-probe.lock'
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$worker=$null
try {
    if (-not $AutomatedSmoke) {
        Write-Host 'Single-stream progress test. Keep CeVIO free until this test is finished.'
        $answer = Read-Host 'Type FREE if CeVIO is available now; Enter cancels'
        if ($answer -cne 'FREE') { Write-Host 'Cancelled; CeVIO was not accessed.'; return }
    }
    # Start a dedicated instance with a private copy, avoiding an old instance
    # consuming the same ready file or sharing its audio ownership.
    $instance = Join-Path $session 'runtime'
    Copy-Item -LiteralPath $runtime -Destination $instance -Recurse
    $speechDir = Join-Path $instance 'speech'
    Get-ChildItem -LiteralPath $speechDir -File | Remove-Item -Force
    Remove-Item -LiteralPath (Join-Path $instance 'speech.ready') -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot 'ProgressQueue.psm1') -Force
    $inbox = Join-Path $session 'inbox'
    $null = New-Item -ItemType Directory -Path $inbox
    $queue = New-ProgressQueue
    $preparing = $null
    $worker = $null
    $received = @{}
    $finished = New-Object 'System.Collections.Generic.List[string]'
    $preview = New-Object Diagnostics.Process
    $preview.StartInfo.FileName = Join-Path $instance 'Demo.exe'
    $preview.StartInfo.WorkingDirectory = $instance
    $preview.StartInfo.UseShellExecute = $false
    $preview.StartInfo.RedirectStandardOutput = $true
    $preview.StartInfo.RedirectStandardError = $true
    if (-not $preview.Start()) { throw 'Renderer process start failed.' }
    $outputRead = $preview.StandardOutput.ReadToEndAsync()
    $errorRead = $preview.StandardError.ReadToEndAsync()
    $startup = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Milliseconds 250
        $preview.Refresh()
        if ($preview.HasExited) { throw 'Renderer exited before readiness.' }
        if ($startup.Elapsed.TotalSeconds -gt 60) { throw 'Renderer window readiness timeout.' }
    } until ($preview.MainWindowHandle -ne 0 -and $preview.Responding)
    $startup.Stop()

    function Record-QueueEvent([string]$Stage,[string]$Id) {
        [ordered]@{ Stage=$Stage; Id=$Id; Utc=[DateTime]::UtcNow.ToString('o') } |
            ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $session 'events.jsonl') -Encoding UTF8
    }
    function Post-SmokeCommand([int]$Sequence,[string]$Id,[string]$Text) {
        $command=[ordered]@{ SessionId=$sessionId; Stream='single-progress-test'; Id=$Id; Sequence=$Sequence; Source='windows-queue-test'; Text=$Text; SentUtc=[DateTime]::UtcNow.ToString('o') }
        $path=Join-Path $inbox (($Sequence.ToString('D10'))+'-'+$Id+'.json')
        [IO.File]::WriteAllText(($path+'.tmp'),($command|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        [IO.File]::Move(($path+'.tmp'),$path)
    }
    function Make-SmokeWave([string]$Path,[int]$Seconds) {
        $stream=[IO.File]::Create($Path)
        $writer=New-Object IO.BinaryWriter($stream)
        try {
            $length=16000*2*$Seconds
            $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $writer.Write([int](36+$length))
            $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $writer.Write([int]16)
            $writer.Write([int16]1); $writer.Write([int16]1); $writer.Write([int]16000); $writer.Write([int]32000)
            $writer.Write([int16]2); $writer.Write([int16]16)
            $writer.Write([Text.Encoding]::ASCII.GetBytes('data')); $writer.Write([int]$length)
            $writer.Write((New-Object byte[] $length))
        } finally { $writer.Dispose(); $stream.Dispose() }
    }
    $self=Get-Process -Id $PID
    $pointer=[ordered]@{ SessionId=$sessionId; ReceiverPid=$PID; ReceiverStartUtc=$self.StartTime.ToUniversalTime().ToString('o'); Directory=$session; Stream='single-progress-test' }
    if (-not $AutomatedSmoke) {
        $pointer | ConvertTo-Json | Set-Content -LiteralPath $sessionPointer -Encoding UTF8
        Write-Host 'WAITING_FOR_PROGRESS. This test accepts one work stream; no restart replay is enabled.'
    }
    $a='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $b='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $c='cccccccccccccccccccccccccccccccc'
    $smokeInjected=$false
    $readyPath=Join-Path $instance 'speech.ready'
    $sessionTimer=[Diagnostics.Stopwatch]::StartNew()
    if ($AutomatedSmoke) { Post-SmokeCommand 1 $a 'A' }
    while ($true) {
        $preview.Refresh()
        if ($preview.HasExited) {
            if ($null -ne $queue.Active -or $null -ne $queue.Ready -or $null -ne $preparing) { throw 'Renderer closed during work; result unknown, no retry.' }
            break
        }
        if ($AutomatedSmoke -and $sessionTimer.Elapsed.TotalSeconds -gt 90) { throw 'Queue smoke timeout.' }
        $gate=$null
        try { $gate=[IO.File]::Open((Join-Path $instance 'speech.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
        catch [IO.IOException] {
            $nativeCode=$_.Exception.HResult -band 65535
            if ($nativeCode -notin @(32,33)) { throw }
        }
        if ($null -ne $gate) {
            try {
                if ($null -ne $queue.Ready) {
                    $id=$queue.Ready.Id
                    if (Test-Path -LiteralPath (Join-Path $speechDir ($id+'.claimed'))) {
                        Set-ProgressActive $queue $id
                        Record-QueueEvent 'active_claimed' $id
                    }
                }
                if ($null -ne $queue.Active) {
                    $id=$queue.Active.Id
                    $statusPath=Join-Path $speechDir ($id+'.status')
                    $events=if(Test-Path -LiteralPath $statusPath){[IO.File]::ReadAllText($statusPath)}else{''}
                    if ($events -match '(failed|missing|unsupported|timeout|regressed|interrupted|wave_size|wave_header|wave_chunk|riff_size|wave_format|duplicate_data|wave_padding|duplicate_suppressed)') { throw 'Native playback failed; no automatic retry.' }
                    if ($events.Contains('playback_completed')) {
                        Complete-Progress $queue $id
                        $finished.Add($id)
                        Record-QueueEvent 'completed' $id
                    } elseif ($AutomatedSmoke -and $id -ceq $a -and $events.Contains('playback_submitted') -and -not $smokeInjected) {
                        Post-SmokeCommand 2 $b 'B'
                        Post-SmokeCommand 3 $c 'C'
                        # A repeated ID/content, in a separate delivery envelope.
                        $duplicate=Join-Path $inbox ('0000000004-'+$a+'.json')
                        $original=Join-Path $inbox ('0000000001-'+$a+'.json')
                        Copy-Item -LiteralPath $original -Destination ($duplicate+'.tmp')
                        [IO.File]::Move(($duplicate+'.tmp'),$duplicate)
                        $smokeInjected=$true
                    }
                }
                foreach ($file in @(Get-ChildItem -LiteralPath $inbox -File -Filter '*.json' | Sort-Object Name)) {
                    if ($received.ContainsKey($file.Name)) { continue }
                    if ($file.Length -gt 4096) { throw 'Notification exceeds size bound.' }
                    $command=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $decision=Add-ProgressNotification $queue $command $sessionId
                    $received[$file.Name]=$true
                    if ($decision.WithdrawReady) {
                        if (Test-Path -LiteralPath $readyPath) { Remove-Item -LiteralPath $readyPath }
                    }
                    Record-QueueEvent $decision.Stage $command.Id
                    if ($decision.Replaced) { Record-QueueEvent 'superseded' $decision.Replaced }
                }
                if ($null -ne $worker) {
                    if ($worker.HasExited) {
                        $worker.WaitForExit()
                        [IO.File]::WriteAllText((Join-Path $session ($preparing.Id+'.worker.log')),$workerOutput.Result)
                        [IO.File]::WriteAllText((Join-Path $session ($preparing.Id+'.worker-error.log')),$workerError.Result)
                        if ($worker.ExitCode -ne 0) { throw 'Synthesis failed; no retry.' }
                        $worker.Dispose(); $worker=$null
                    }
                }
                if ($null -ne $preparing -and $null -eq $worker) {
                    $id=$preparing.Id
                    if (Set-ProgressReady $queue $id) {
                        Record-QueueEvent 'synthesized' $id
                        [IO.File]::WriteAllText(($readyPath+'.tmp'),$id,[Text.Encoding]::ASCII)
                        [IO.File]::Move(($readyPath+'.tmp'),$readyPath)
                        Record-QueueEvent 'ready' $id
                    } else {
                        Record-QueueEvent 'synthesis_discarded' $id
                    }
                    $preparing=$null
                }
                if ($null -eq $queue.Active -and $null -eq $queue.Ready -and $null -eq $preparing -and $null -ne $queue.Pending) {
                    $preparing=$queue.Pending
                    Record-QueueEvent 'synthesis_started' $preparing.Id
                    if ($AutomatedSmoke) {
                        $seconds=if($preparing.Id -ceq $a){3}else{1}
                        Make-SmokeWave (Join-Path $speechDir ($preparing.Id+'.wav')) $seconds
                    } else {
                        $commandPath=Join-Path $session ($preparing.Id+'.command.json')
                        $preparing | ConvertTo-Json | Set-Content -LiteralPath $commandPath -Encoding UTF8
                        $worker=New-Object Diagnostics.Process
                        $worker.StartInfo.FileName=Join-Path $PSHOME 'powershell.exe'
                        $worker.StartInfo.Arguments='-NoProfile -File "'+(Join-Path $PSScriptRoot 'Synthesize-AgentSpeech.ps1')+'" -CommandPath "'+$commandPath+'" -OutputDirectory "'+$speechDir+'" -CeVIOIsFree'
                        $worker.StartInfo.UseShellExecute=$false
                        $worker.StartInfo.RedirectStandardOutput=$true
                        $worker.StartInfo.RedirectStandardError=$true
                        if(-not $worker.Start()){throw 'Synthesis worker start failed.'}
                        $workerOutput=$worker.StandardOutput.ReadToEndAsync()
                        $workerError=$worker.StandardError.ReadToEndAsync()
                    }
                }
            } finally { $gate.Dispose() }
        }
        if ($AutomatedSmoke -and $finished.Count -eq 2) {
            if ($finished[0] -cne $a -or $finished[1] -cne $c -or -not $smokeInjected) { throw 'Wrong playback order.' }
            if (Test-Path -LiteralPath (Join-Path $speechDir ($b+'.claimed'))) { throw 'Superseded B reached native playback.' }
            $allEvents=Get-Content -LiteralPath (Join-Path $session 'events.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
            if (@($allEvents | Where-Object { $_.Stage -eq 'duplicate' -and $_.Id -ceq $a }).Count -ne 1) { throw 'Duplicate was not suppressed.' }
            if (-not $preview.CloseMainWindow() -or -not $preview.WaitForExit(10000) -or $preview.ExitCode -ne 0) { throw 'Own-window close failed.' }
            [ordered]@{ Kind='single_stream_queue_native_smoke'; Played=@('A','C'); BSubmitted=$false; DuplicateSuppressed=$true; CeVIOAccessed=$false; VisualAcceptance='not_observed' } | ConvertTo-Json
            break
        }
        Start-Sleep -Milliseconds 30
    }
    $preview.WaitForExit()
    [IO.File]::WriteAllText((Join-Path $session 'render.log'),$outputRead.Result)
    [IO.File]::WriteAllText((Join-Path $session 'render-error.log'),$errorRead.Result)
    if ($preview.ExitCode -ne 0) { throw 'Renderer exited with an error.' }
} finally {
    if (Test-Path -LiteralPath $sessionPointer) {
        $pointer=Get-Content -LiteralPath $sessionPointer -Raw -Encoding UTF8 | ConvertFrom-Json
        if($pointer.SessionId -ceq $sessionId){Remove-Item -LiteralPath $sessionPointer}
    }
    if ($null -ne $worker -and -not $worker.HasExited) {
        # Let this worker finish instead of interrupting an external CeVIO call.
        $worker.WaitForExit()
    }
    $lock.Dispose()
}
