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
$delegatePath=Join-Path $source 'LAppDelegate.cpp'

$model=Read-Normalized $modelPath
$agentHomeInclude='#include "AgentHome.hpp"'
$agentBgmInclude='#include "AgentBgm.hpp"'
if(-not $model.Contains($agentBgmInclude)){
    $model=Replace-ExactlyOnce $model $agentHomeInclude ($agentHomeInclude+"`n"+$agentBgmInclude) 'AgentBgm include'
}
$configureLine='    _agentHome->Configure(dir);'
$oldBgmLine='    AgentBgm::EnsureStarted("home-audio/bgm00_system01.wav");'
$newBgmLine='    AgentBgm::EnsureStarted();'
if($model.Contains($oldBgmLine)){
    $model=$model.Replace($oldBgmLine,$newBgmLine)
}
elseif(-not $model.Contains($newBgmLine)){
    $model=Replace-ExactlyOnce $model $configureLine ($configureLine+"`n"+$newBgmLine) 'BGM startup'
}
Write-Bom $modelPath $model

$delegate=Read-Normalized $delegatePath
$delegateInclude='#include "LAppDelegate.hpp"'
if(-not $delegate.Contains($agentBgmInclude)){
    $delegate=Replace-ExactlyOnce $delegate $delegateInclude ($delegateInclude+"`n"+$agentBgmInclude) 'AgentBgm delegate include'
}
if(-not $delegate.Contains('AgentBgm::Cycle();')){
    $mouseMarker='    case WM_MOUSEMOVE:'
    $keyBlock=@'
    case WM_KEYUP:
        if (wParam == 'B')
        {
            AgentBgm::Cycle();
            return 0;
        }
        break;

'@
    $delegate=Replace-ExactlyOnce $delegate $mouseMarker ($keyBlock+$mouseMarker) 'B key BGM selector'
}
Write-Bom $delegatePath $delegate

$view=Read-Normalized $viewPath
$old='fHeight = static_cast<float>(height) * 0.95f;'
$count=([regex]::Matches($view,[regex]::Escape($old))).Count
if($count -eq 2){$view=$view.Replace($old,'fHeight = static_cast<float>(height);')}
elseif($count -ne 0){throw ('Unexpected background height marker count: '+$count)}
Write-Bom $viewPath $view

$modelCheck=Read-Normalized $modelPath
$viewCheck=Read-Normalized $viewPath
$delegateCheck=Read-Normalized $delegatePath
if(-not $modelCheck.Contains($agentBgmInclude)){throw 'AgentBgm include missing.'}
if(-not $modelCheck.Contains($newBgmLine)){throw 'BGM startup missing.'}
if(-not $delegateCheck.Contains('AgentBgm::Cycle();')){throw 'B-key BGM selector missing.'}
if($viewCheck.Contains('static_cast<float>(height) * 0.95f')){throw 'Background still scaled to 95 percent.'}
Write-Output 'MAGIRECO_HOME_MEDIA_SOURCE_INTEGRATION_APPLIED'
Write-Output 'background_fill=true bgm_default=bgm01_anime06 bgm_alt=bgm00_system01 selector=B loop=true'
