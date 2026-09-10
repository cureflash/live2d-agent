[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$base=Join-Path $env:LOCALAPPDATA 'live2d-agent'
$statePath=Join-Path $base 'magireco-home-build.json'
if(-not(Test-Path -LiteralPath $statePath)){throw 'Magireco home runtime is not installed.'}
$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json
$runtime=[IO.Path]::GetFullPath([string]$state.WorkingDirectory)
if(-not $runtime.StartsWith($base+'\magireco-home-runtime-',[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected home runtime path.'}
$exe=Join-Path $runtime 'Demo.exe'
if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Home renderer executable not found.'}
foreach($name in @('model.model3.json','model.pose3.json')){
    if(-not(Test-Path -LiteralPath (Join-Path $runtime ('Resources\model\'+$name)) -PathType Leaf)){throw ($name+' not found.')}
}
$audioDir=Join-Path $runtime 'home-audio'
$required=@(24)+@(33..41)
foreach($number in $required){
    $name=('vo_char_2001_00_{0:D2}.wav' -f $number)
    if(-not(Test-Path -LiteralPath (Join-Path $audioDir $name) -PathType Leaf)){throw ('Missing home voice: '+$name)}
}
$speechDir=Join-Path $runtime 'speech'
if(-not(Test-Path -LiteralPath $speechDir)){$null=New-Item -ItemType Directory -Path $speechDir}
Remove-Item -LiteralPath (Join-Path $runtime 'speech.ready') -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $speechDir -File -ErrorAction SilentlyContinue|Where-Object {$_.Name -match '\.(wav|claimed|ephemeral)$'}|Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host 'Magireco-style home: startup voice + Talk1-9 random tap. CeVIO is not used.'
$p=Start-Process -FilePath $exe -WorkingDirectory $runtime -PassThru
$p.WaitForExit()
if($p.ExitCode -ne 0){throw ('Renderer exited with code '+$p.ExitCode)}
