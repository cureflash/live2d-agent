# Read-only discovery; no applications, DLLs, ADB, or Nox instances are started.
# Windows PowerShell 5.1. Windows execution and syntax validation remain pending.
[CmdletBinding()]
param([string[]]$AdditionalModelRoots = @())
$ErrorActionPreference = 'Stop'
$discoveryErrors = New-Object 'System.Collections.Generic.List[string]'
$apps = @()
$registryRoots = @(
 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)
foreach ($registryRoot in $registryRoots) {
 if (Test-Path -LiteralPath $registryRoot) {
  foreach ($entry in Get-ChildItem -LiteralPath $registryRoot) {
   try {
    $info = Get-ItemProperty -LiteralPath $entry.PSPath
    if ($info.DisplayName -match 'CeVIO|Cubism|Live2D|Nox') {
     $apps += [pscustomobject]@{Name=$info.DisplayName; Version=$info.DisplayVersion; InstallLocation=$info.InstallLocation}
    }
   } catch { $discoveryErrors.Add('Could not read one installed-application registry entry.') }
  }
 }
}
$modelRoots = @(
 [Environment]::GetFolderPath('Desktop'),
 [Environment]::GetFolderPath('MyDocuments'),
 (Join-Path $env:USERPROFILE 'Downloads')
) + $AdditionalModelRoots
$modelCandidates = @()
foreach ($modelRoot in ($modelRoots | Where-Object { $_ } | Select-Object -Unique)) {
 if (-not (Test-Path -LiteralPath $modelRoot -PathType Container)) { continue }
 # Traverse explicitly to skip junctions/symlinks and avoid leaving requested roots.
 $stack = New-Object 'System.Collections.Generic.Stack[string]'
 $stack.Push($modelRoot)
 while ($stack.Count -gt 0) {
  $directory = $stack.Pop()
  try { $children = @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop) }
  catch { $discoveryErrors.Add('Could not list directory: ' + $directory); continue }
  foreach ($child in $children) {
   if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
   if ($child.PSIsContainer) { $stack.Push($child.FullName); continue }
   if ($child.Name -match '\.(moc3?|mtn|cmo3|cmox)$|\.model3?\.json$') {
    $modelCandidates += [pscustomobject]@{Path=$child.FullName; Bytes=$child.Length}
   }
  }
 }
}
[pscustomobject]@{
 Kind='read_only_inventory_not_playback_validation'
 ObservedUtc=[DateTime]::UtcNow.ToString('o')
 Is64BitProcess=[Environment]::Is64BitProcess
 UserInteractive=[Environment]::UserInteractive
 SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
 PowerShellVersion=$PSVersionTable.PSVersion.ToString()
 InstalledApplications=$apps
 SearchedModelRoots=$modelRoots
 ModelCandidates=$modelCandidates
 DiscoveryErrors=@($discoveryErrors.ToArray())
 Limitations=@('Only uninstall registry and named folders searched.', 'No match does not mean not installed.', 'Nox internal files were not inspected.', 'Audio endpoint, CeVIO license and SDK compatibility not tested.')
} | ConvertTo-Json -Depth 6
