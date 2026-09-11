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
if(-not $model.Contains('#include "AgentBgm.hpp"')){
    $model=Replace-ExactlyOnce $model "#include \"AgentHome.hpp\"`n" "#include \"AgentHome.hpp\"`n#include \"AgentBgm.hpp\"`n" 'AgentBgm include'
}
if(-not $model.Contains('AgentBgm::EnsureStarted("home-audio/bgm00_system01.wav");')){
    $model=Replace-ExactlyOnce $model "    _agentHome->Configure(dir);`n" "    _agentHome->Configure(dir);`n    AgentBgm::EnsureStarted(\"home-audio/bgm00_system01.wav\");`n" 'BGM startup'
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
if(-not $modelCheck.Contains('#include "AgentBgm.hpp"')){throw 'AgentBgm include missing.'}
if(-not $modelCheck.Contains('AgentBgm::EnsureStarted("home-audio/bgm00_system01.wav");')){throw 'BGM startup missing.'}
if($viewCheck.Contains('static_cast<float>(height) * 0.95f')){throw 'Background still scaled to 95 percent.'}
Write-Output 'MAGIRECO_HOME_MEDIA_SOURCE_INTEGRATION_APPLIED'
Write-Output 'background_fill=true bgm=bgm00_system01 loop=true'
