[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Read-Normalized([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw ('Source file missing: '+$Path)}
    return [IO.File]::ReadAllText($Path).Replace("`r`n","`n")
}
function Replace-ExactlyOnce([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $first=$Text.IndexOf($Old,[StringComparison]::Ordinal)
    if($first -lt 0){throw ('Expected marker not found: '+$Label)}
    $second=$Text.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal)
    if($second -ge 0){throw ('Marker not unique: '+$Label)}
    return $Text.Substring(0,$first)+$New+$Text.Substring($first+$Old.Length)
}
function Write-Bom([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($true)))}

$source=[IO.Path]::GetFullPath($SourceRoot)
$modelPath=Join-Path $source 'LAppModel.cpp'
$viewPath=Join-Path $source 'LAppView.cpp'

$model=Read-Normalized $modelPath
$agentHomeInclude='#include "AgentHome.hpp"'
$agentBgmInclude='#include "AgentBgm.hpp"'
if(-not $model.Contains($agentBgmInclude)){
    $model=Replace-ExactlyOnce $model $agentHomeInclude ($agentHomeInclude+"`n"+$agentBgmInclude) 'AgentBgm include'
}
$configureLine='    _agentHome->Configure(dir);'
$bgmLine='    AgentBgm::EnsureStarted("home-audio/bgm00_system01.wav");'
if(-not $model.Contains($bgmLine)){
    $model=Replace-ExactlyOnce $model $configureLine ($configureLine+"`n"+$bgmLine) 'BGM startup'
}
Write-Bom $modelPath $model

$view=Read-Normalized $viewPath
$old='fHeight = static_cast<float>(height) * 0.95f;'
$count=([regex]::Matches($view,[regex]::Escape($old))).Count
if($count -eq 2){$view=$view.Replace($old,'fHeight = static_cast<float>(height);')}
elseif($count -ne 0){throw ('Unexpected background height marker count: '+$count)}
Write-Bom $viewPath $view

$modelCheck=Read-Normalized $modelPath
$viewCheck=Read-Normalized $viewPath
if(-not $modelCheck.Contains($agentBgmInclude)){throw 'AgentBgm include missing.'}
if(-not $modelCheck.Contains($bgmLine)){throw 'BGM startup missing.'}
if($viewCheck.Contains('static_cast<float>(height) * 0.95f')){throw 'Background still scaled to 95 percent.'}
Write-Output 'MAGIRECO_HOME_MEDIA_SOURCE_INTEGRATION_APPLIED'
Write-Output 'background_fill=true bgm=bgm00_system01 loop=true'
