Set-StrictMode -Version Latest
function New-ProgressQueue {
    return @{ HighWater=[long]0; Seen=@{}; Pending=$null; Ready=$null; Active=$null }
}
function Add-ProgressNotification {
    param([hashtable]$Queue, $Command, [string]$SessionId)
    if ($Command.SessionId -cne $SessionId -or $Command.Stream -cne 'single-progress-test' -or
        $Command.Id -cnotmatch '^[0-9a-f]{32}$' -or
        ($Command.Sequence -isnot [long] -and $Command.Sequence -isnot [int]) -or
        $Command.Sequence -le 0 -or $Command.Text -isnot [string] -or
        [string]::IsNullOrWhiteSpace($Command.Text) -or $Command.Text.Length -gt 280 -or
        $Command.Source -notin @('web-chatgpt-work-test','windows-queue-test')) { throw 'Invalid progress notification.' }
    $canonical = [ordered]@{ Sequence=$Command.Sequence; Text=$Command.Text; Source=$Command.Source; Stream=$Command.Stream } | ConvertTo-Json -Compress
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $digest = [Convert]::ToBase64String($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))) } finally { $hash.Dispose() }
    if ($Queue.Seen.ContainsKey($Command.Id)) {
        if ($Queue.Seen[$Command.Id] -cne $digest) { throw 'Command ID collision.' }
        return [pscustomobject]@{ Stage='duplicate'; Replaced=$null; WithdrawReady=$false }
    }
    $Queue.Seen[$Command.Id]=$digest
    if ($Command.Sequence -le $Queue.HighWater) {
        return [pscustomobject]@{ Stage='stale'; Replaced=$null; WithdrawReady=$false }
    }
    $Queue.HighWater=[long]$Command.Sequence
    $replaced = if ($null -ne $Queue.Pending) { $Queue.Pending.Id } elseif ($null -ne $Queue.Ready) { $Queue.Ready.Id } else { $null }
    $withdraw = $null -ne $Queue.Ready
    $Queue.Ready=$null
    $Queue.Pending=$Command
    return [pscustomobject]@{ Stage='accepted'; Replaced=$replaced; WithdrawReady=$withdraw }
}
function Set-ProgressReady {
    param([hashtable]$Queue, [string]$Id)
    if ($null -ne $Queue.Active -or $null -ne $Queue.Ready) { throw 'Playback slot occupied.' }
    if ($null -eq $Queue.Pending -or $Queue.Pending.Id -cne $Id) { return $false }
    $Queue.Ready=$Queue.Pending
    $Queue.Pending=$null
    return $true
}
function Set-ProgressActive {
    param([hashtable]$Queue, [string]$Id)
    if ($null -ne $Queue.Active -or $null -eq $Queue.Ready -or $Queue.Ready.Id -cne $Id) { throw 'Unexpected native claim.' }
    $Queue.Active=$Queue.Ready
    $Queue.Ready=$null
}
function Complete-Progress {
    param([hashtable]$Queue, [string]$Id)
    if ($null -eq $Queue.Active -or $Queue.Active.Id -cne $Id) { throw 'Unexpected native completion.' }
    $Queue.Active=$null
}
Export-ModuleMember -Function New-ProgressQueue,Add-ProgressNotification,Set-ProgressReady,Set-ProgressActive,Complete-Progress
