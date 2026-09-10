$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ProgressQueue.psm1') -Force
function Assert([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message} }
function Cmd([int]$Sequence,[string]$Id,[string]$Text='test') {
    return [pscustomobject]@{ SessionId='session'; Stream='single-progress-test'; Id=$Id; Sequence=$Sequence; Source='windows-queue-test'; Text=$Text }
}
$a='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; $b='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'; $c='cccccccccccccccccccccccccccccccc'
$q=New-ProgressQueue
$null=Add-ProgressNotification $q (Cmd 1 $a) 'session'
Assert (Set-ProgressReady $q $a) 'A must become ready'
Set-ProgressActive $q $a
$null=Add-ProgressNotification $q (Cmd 2 $b) 'session'
$r=Add-ProgressNotification $q (Cmd 3 $c) 'session'
Assert ($r.Replaced -ceq $b -and $q.Active.Id -ceq $a -and $q.Pending.Id -ceq $c) 'A must survive B/C replacement'
$r=Add-ProgressNotification $q (Cmd 1 $a) 'session'
Assert ($r.Stage -eq 'duplicate' -and $q.Pending.Id -ceq $c) 'Duplicate must not alter pending'
Complete-Progress $q $a
Assert (Set-ProgressReady $q $c) 'C must be next'
Set-ProgressActive $q $c
Complete-Progress $q $c
Assert ($null -eq $q.Active -and $null -eq $q.Pending) 'Queue must drain'
$q=New-ProgressQueue
$null=Add-ProgressNotification $q (Cmd 1 $a) 'session'
# New arrival during synthesis: old result must not become ready.
$null=Add-ProgressNotification $q (Cmd 2 $b) 'session'
Assert (-not (Set-ProgressReady $q $a)) 'Obsolete synthesis must be discarded'
Assert (Set-ProgressReady $q $b) 'Latest synthesis may become ready'
$r=Add-ProgressNotification $q (Cmd 3 $c) 'session'
Assert ($r.WithdrawReady -and $r.Replaced -ceq $b -and $null -eq $q.Ready) 'Unclaimed ready must be replaceable'
$bad=$false
try { $null=Add-ProgressNotification $q (Cmd 3 $c 'different') 'session' } catch { $bad=$true }
Assert $bad 'Changed duplicate must fail'
$old=Add-ProgressNotification $q (Cmd 2 'dddddddddddddddddddddddddddddddd') 'session'
Assert ($old.Stage -eq 'stale' -and $q.Pending.Id -ceq $c) 'Out-of-order message must not replace newer one'
$bad=$false
try { $null=Add-ProgressNotification $q (Cmd 4 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee') 'wrong-session' } catch { $bad=$true }
Assert $bad 'Wrong session must fail'
$bad=$false
try { Complete-Progress $q $a } catch { $bad=$true }
Assert $bad 'Unexpected completion must fail'
Write-Output 'PROGRESS_QUEUE_STATE_TESTS_PASSED'
