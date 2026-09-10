# Interactive audition only. This is not the notification app or synchronized lip sync.
[CmdletBinding()]
param([switch]$PrepareOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$base = Join-Path $env:LOCALAPPDATA 'live2d-agent'
$state = Get-Content -LiteralPath (Join-Path $base 'private-model.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$source = [IO.Path]::GetFullPath([string]$state.WorkingDirectory)
if (-not $source.StartsWith($base + '\private-', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected private runtime.' }
$configRelative = 'Resources\model\model.model3.json'
$config = Get-Content -LiteralPath (Join-Path $source $configRelative) -Raw -Encoding UTF8 | ConvertFrom-Json
$choices = @(
    foreach ($group in $config.FileReferences.Motions.PSObject.Properties) {
        $index = 0
        foreach ($motion in $group.Value) {
            [pscustomobject]@{ Group = $group.Name; Index = $index; Entry = $motion }
            $index++
        }
    }
)
if ($choices.Count -eq 0) { throw 'No motions in model configuration.' }
if ($PrepareOnly) {
    if (-not (Test-Path -LiteralPath (Join-Path $source 'Demo.exe') -PathType Leaf)) { throw 'Private executable missing.' }
    [pscustomobject]@{ Kind = 'audition_preflight_not_playback'; MotionCount = $choices.Count; CeVIOAccessed = $false } | ConvertTo-Json
    return
}
Write-Host 'Motion audition. These are numbered trials, not confirmed idle gestures.'
for ($i = 0; $i -lt $choices.Count; $i++) {
    Write-Host ('{0}: group={1}, index={2}' -f $i, $choices[$i].Group, $choices[$i].Index)
}
$selected = -1
$answer = Read-Host 'Choose a motion number'
if (-not [int]::TryParse($answer, [ref]$selected) -or $selected -lt 0 -or $selected -ge $choices.Count) { throw 'Invalid motion number.' }
# A private, disposable model adapter lets the unmodified official sample audition
# exactly the chosen motion via its Idle slot. Never change the source model.
$runtime = Join-Path $base ('audition-' + [guid]::NewGuid().ToString('N'))
Copy-Item -LiteralPath $source -Destination $runtime -Recurse
$entry = [pscustomobject]@{ File = [string]$choices[$selected].Entry.File }
$config.FileReferences.Motions | Add-Member -MemberType NoteProperty -Name Idle -Value @($entry) -Force
$config | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Join-Path $runtime $configRelative) -Encoding UTF8
Write-Host 'The selected motion repeats for inspection. Close this new window when finished.'
Write-Host 'Existing model windows are not closed. Speech is an independent test, without synchronized lip sync.'
$preview = Start-Process -FilePath (Join-Path $runtime 'Demo.exe') -WorkingDirectory $runtime -PassThru
try {
    $voice = Read-Host 'Is CeVIO FREE of makemovie and all other work NOW? Type FREE to play one voice test, or Enter to skip'
    if ($voice -ceq 'FREE') {
        $dll = Join-Path $env:ProgramFiles 'CeVIO\CeVIO Creative Studio (64bit)\CeVIO.Talk.RemoteService.DLL'
        $cast = -join ([char[]]@(0x3055,0x3068,0x3046,0x3055,0x3055,0x3089))
        # "Movement and voice are being checked. Lip synchronization is still to come."
        $speech = -join ([char[]]@(0x52d5,0x304d,0x3068,0x58f0,0x3092,0x78ba,0x8a8d,0x3057,0x3066,0x3044,0x308b,0x3088,0x3002,0x53e3,0x30d1,0x30af,0x306e,0x540c,0x671f,0x306f,0x3001,0x3053,0x308c,0x304b,0x3089,0x3060,0x3088,0x3002))
        & (Join-Path $PSHOME 'powershell.exe') -NoProfile -File (Join-Path $PSScriptRoot 'Test-CeVIO.ps1') -DllPath $dll -Cast $cast -Text $speech -CeVIOIsFree
        if ($LASTEXITCODE -ne 0) { throw 'Voice probe failed.' }
    } else {
        Write-Host 'CeVIO was not accessed.'
    }
    Write-Host 'Observe the motion, then close the new model window.'
    $preview.WaitForExit()
    if ($preview.ExitCode -ne 0) { throw 'Preview exited with an error.' }
} finally {
    # Never stop a user window or the CeVIO host. Keep diagnostics locally on failure.
    if ($preview.HasExited) { Remove-Item -LiteralPath $runtime -Recurse -Force }
}
