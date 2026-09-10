[CmdletBinding()]
param([switch]$AutomatedSmoke,[switch]$PrepareOnly,[switch]$ExpressionSmoke)
if($ExpressionSmoke){$AutomatedSmoke=$true}
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'LocalPcmWave.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'CubismJsonImport.psm1') -Force
$base=Join-Path $env:LOCALAPPDATA 'live2d-agent'
$built=Get-Content -LiteralPath (Join-Path $base 'expression-build.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$bank=Get-Content -LiteralPath (Join-Path $base 'madoka-voice-bank.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$voices=@($bank.Clips)
if($voices.Count -eq 0){throw 'No converted local voice clips.'}
$source=[IO.Path]::GetFullPath([string]$built.WorkingDirectory)
if(-not $source.StartsWith($base+'\expression-runtime-',[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected source runtime.'}
$configRelative='Resources\model\model.model3.json'
$config=Get-Content -LiteralPath (Join-Path $source $configRelative) -Raw -Encoding UTF8 | ConvertFrom-Json
$motions=@(foreach($group in $config.FileReferences.Motions.PSObject.Properties){
    $index=0
    foreach($entry in $group.Value){
        # Keep file-based motions only; no official sample Sound playback.
        [pscustomobject]@{Group=$group.Name;Index=$index;File=[string]$entry.File}
        $index++
    }
})
$expressions=@($config.FileReferences.Expressions)
if($expressions.Count -eq 0){throw 'No expressions in model configuration.'}
if($motions.Count -eq 0){throw 'Model has no motions.'}
foreach($clip in $voices){$null=Get-LocalPcmWaveInfo ([string]$clip.WavePath)}
foreach($motion in $motions){
    if(-not(Test-Path -LiteralPath (Join-Path (Join-Path $source 'Resources\model') $motion.File) -PathType Leaf)){throw 'Motion file missing.'}
}
if($PrepareOnly){
    [pscustomobject]@{Kind='local_voice_preflight_not_playback';Voices=$voices.Count;Motions=$motions.Count;CeVIOAccessed=$false}|ConvertTo-Json
    return
}
$motionIndex=0
if(-not $AutomatedSmoke){
    Write-Host 'Local recorded voice + Live2D motion. CeVIO is not used.'
    Write-Host 'Numbered motions are auditions; their meanings are not yet confirmed.'
    for($i=0;$i -lt $motions.Count;$i++){Write-Host ("{0}: {1} [{2}]" -f $i,$motions[$i].Group,$motions[$i].Index)}
    $answer=Read-Host 'Motion number (Enter = 0)'
    if($answer -ne '' -and (-not [int]::TryParse($answer,[ref]$motionIndex) -or $motionIndex -lt 0 -or $motionIndex -ge $motions.Count)){throw 'Invalid motion number.'}
}
$session=Join-Path $base ('local-voice-session-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $session
$instance=Join-Path $session 'runtime'
Copy-Item -LiteralPath $source -Destination $instance -Recurse
$expressionDir=Join-Path $instance 'expression'
$null=New-Item -ItemType Directory -Path $expressionDir -Force
Get-ChildItem -LiteralPath $expressionDir -File | Remove-Item -Force
Remove-Item -LiteralPath (Join-Path $instance 'expression.ready') -ErrorAction SilentlyContinue
$speechDir=Join-Path $instance 'speech'
if(-not(Test-Path -LiteralPath $speechDir)){$null=New-Item -ItemType Directory -Path $speechDir}
Get-ChildItem -LiteralPath $speechDir -File | Remove-Item -Force
Remove-Item -LiteralPath (Join-Path $instance 'speech.ready') -ErrorAction SilentlyContinue
foreach($group in $config.FileReferences.Motions.PSObject.Properties){
    foreach($entry in $group.Value){$entry.PSObject.Properties.Remove('Sound')}
}
$config.FileReferences.Motions | Add-Member -MemberType NoteProperty -Name Idle -Value @([pscustomobject]@{File=$motions[$motionIndex].File}) -Force
[IO.File]::WriteAllText((Join-Path $instance $configRelative),($config|ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding($false)))
Convert-PrivateModelJson (Join-Path $instance 'Resources\model')
$preview=New-Object Diagnostics.Process
$preview.StartInfo.FileName=Join-Path $instance 'Demo.exe'
$preview.StartInfo.WorkingDirectory=$instance
$preview.StartInfo.UseShellExecute=$false
$preview.StartInfo.RedirectStandardOutput=$true
$preview.StartInfo.RedirectStandardError=$true
if(-not $preview.Start()){throw 'Renderer did not start.'}
$outputRead=$preview.StandardOutput.ReadToEndAsync()
$errorRead=$preview.StandardError.ReadToEndAsync()
try {
    $startup=[Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Milliseconds 250
        $preview.Refresh()
        if($preview.HasExited){throw 'Renderer exited before readiness.'}
        if($startup.Elapsed.TotalSeconds -gt 60){throw 'Renderer readiness timeout.'}
    } until($preview.MainWindowHandle -ne 0 -and $preview.Responding)
    $startup.Stop()
    function Send-ExpressionChoice([int]$Index,[string]$Expected='evaluated'){
        $commandId=[guid]::NewGuid().ToString('N')
        $ready=Join-Path $instance 'expression.ready'
        [IO.File]::WriteAllText(($ready+'.tmp'),($commandId+' '+$Index),[Text.Encoding]::ASCII)
        [IO.File]::Move(($ready+'.tmp'),$ready)
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $status=''
        do{
            Start-Sleep -Milliseconds 50
            $preview.Refresh()
            if($preview.HasExited){throw 'Renderer closed during expression selection.'}
            $statusPath=Join-Path $expressionDir ($commandId+'.status')
            if(Test-Path -LiteralPath $statusPath){$status=[IO.File]::ReadAllText($statusPath)}
            if($status.Contains($Expected)){break}
            if($status -match '(missing|empty|failed|invalid|rejected)'){throw 'Expression selection rejected; inspect local status.'}
            if($clock.Elapsed.TotalSeconds -gt 10){throw 'Expression acknowledgement timeout.'}
        }while($true)
        Write-Host ('EXPRESSION_'+$Expected.ToUpperInvariant()+' index='+$Index)
        return $status
    }
    if($ExpressionSmoke){
        for($i=0;$i -lt $expressions.Count;$i++){$null=Send-ExpressionChoice $i}
        $null=Send-ExpressionChoice $expressions.Count 'invalid_index'
        Write-Host ('EXPRESSION_TEST_PASSED count='+$expressions.Count+' invalid_index_rejected=True')
    }
    if(-not $AutomatedSmoke){
        for($i=0;$i -lt $voices.Count;$i++){Write-Host ("{0}: {1} ({2:N1}s)" -f $i,$voices[$i].Name,$voices[$i].Seconds)}
        for($i=0;$i -lt $expressions.Count;$i++){Write-Host ('e '+$i+': '+$expressions[$i].Name)}
        Write-Host 'Voice: number or Enter=0. Expression: e number. Close: q.'
        Write-Host 'Each selected clip plays once, to completion. Select again to replay.'
    }
    $played=0
    while(-not $preview.HasExited){
        $voiceIndex=0
        if(-not $AutomatedSmoke){
            $answer=Read-Host 'Voice number / e number'
            $preview.Refresh()
            if($preview.HasExited){break}
            $expressionCommand=[regex]::Match($answer,'^e\s+([0-9]+)$')
            if($expressionCommand.Success){
                $expressionIndex=-1
                if(-not [int]::TryParse($expressionCommand.Groups[1].Value,[ref]$expressionIndex) -or $expressionIndex -ge $expressions.Count){Write-Host 'Invalid expression number.';continue}
                $null=Send-ExpressionChoice $expressionIndex
                continue
            }
            if($answer -ceq 'q'){$null=$preview.CloseMainWindow();break}
            if($answer -ne '' -and (-not [int]::TryParse($answer,[ref]$voiceIndex) -or $voiceIndex -lt 0 -or $voiceIndex -ge $voices.Count)){Write-Host 'Invalid voice number.';continue}
        }
        $clip=$voices[$voiceIndex]
        $info=Get-LocalPcmWaveInfo ([string]$clip.WavePath)
        $id=[guid]::NewGuid().ToString('N')
        Copy-Item -LiteralPath $clip.WavePath -Destination (Join-Path $speechDir ($id+'.wav'))
        $ready=Join-Path $instance 'speech.ready'
        [IO.File]::WriteAllText(($ready+'.tmp'),$id,[Text.Encoding]::ASCII)
        [IO.File]::Move(($ready+'.tmp'),$ready)
        $timer=[Diagnostics.Stopwatch]::StartNew()
        $events=''
        do {
            Start-Sleep -Milliseconds 50
            $preview.Refresh()
            if($preview.HasExited){throw 'Renderer closed during playback; no retry.'}
            $path=Join-Path $speechDir ($id+'.status')
            if(Test-Path -LiteralPath $path){$events=[IO.File]::ReadAllText($path)}
            if($events -match '(failed|missing|unsupported|timeout|regressed|interrupted|wave_size|wave_header|wave_chunk|riff_size|wave_format|duplicate_data|wave_padding)'){throw 'Native voice playback failed; inspect local status.'}
            if($timer.Elapsed.TotalSeconds -gt ($info.Seconds+30)){throw 'Voice playback timeout.'}
        } until($events.Contains('playback_completed'))
        if(-not $events.Contains('device_position_advanced')){throw 'No advancing audio device position.'}
        [ordered]@{Id=$id;Clip=$clip.Name;Motion=$motionIndex;PlaybackCompleted=$true;ObservedUtc=[DateTime]::UtcNow.ToString('o');AudibleAndVisual='requires_user_confirmation';CeVIOAccessed=$false} |
            ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $session 'playback.jsonl') -Encoding UTF8
        $played++
        Write-Host 'PLAYBACK_COMPLETED'
        if($AutomatedSmoke){
            if(-not $preview.CloseMainWindow() -or -not $preview.WaitForExit(10000)){throw 'Own test window did not close.'}
            [ordered]@{Kind='local_recorded_voice_native_test';PlaybackCompleted=$true;DevicePositionAdvanced=$true;NativeStatus=$events;StartupMs=$startup.ElapsedMilliseconds;CeVIOAccessed=$false;VoiceIdentityAndMotionQuality='requires_user_confirmation'}|ConvertTo-Json
            break
        }
    }
    if(-not $preview.WaitForExit(10000)){throw 'Close this model window to finish.'}
    if($preview.ExitCode -ne 0){throw 'Renderer failed.'}
} finally {
    # No access to CeVIO; never stop existing windows or other applications.
    if($preview.HasExited){
        [IO.File]::WriteAllText((Join-Path $session 'render.log'),$outputRead.Result)
        [IO.File]::WriteAllText((Join-Path $session 'render-error.log'),$errorRead.Result)
        $preview.Dispose()
    }
}
