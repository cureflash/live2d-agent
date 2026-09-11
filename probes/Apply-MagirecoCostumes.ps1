[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Read-Normalized([string]$Path) {
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw ('Source file missing: '+$Path)}
    return [IO.File]::ReadAllText($Path).Replace("`r`n","`n")
}

function Replace-ExactlyOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $first=$Text.IndexOf($Old,[StringComparison]::Ordinal)
    if($first -lt 0){throw ('Expected source marker not found: '+$Label)}
    $second=$Text.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal)
    if($second -ge 0){throw ('Source marker is not unique: '+$Label)}
    return $Text.Substring(0,$first)+$New+$Text.Substring($first+$Old.Length)
}

function Write-Utf8Bom([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($true)))
}

$source=[IO.Path]::GetFullPath($SourceRoot)
$viewPath=Join-Path $source 'LAppView.cpp'
$view=Read-Normalized $viewPath
$view=Replace-ExactlyOnce $view @'
        live2DManager->OnTap(x, y);

        // 歯車にタップしたか
'@ @'
        if (_gear->IsHit(px, py, width, height))
        {
            live2DManager->NextScene();
            return;
        }
        live2DManager->OnTap(x, y);

        // 歯車にタップしたか
'@ 'LAppView.cpp costume switch before home tap'
Write-Utf8Bom $viewPath $view

$check=Read-Normalized $viewPath
if(-not $check.Contains('live2DManager->NextScene();')){throw 'Costume switch route missing.'}
if(-not $check.Contains('            return;')){throw 'Costume switch early return missing.'}
$early=@'
        if (_gear->IsHit(px, py, width, height))
        {
            live2DManager->NextScene();
            return;
        }
        live2DManager->OnTap(x, y);
'@
if(-not $check.Contains($early)){throw 'Gear-to-costume switch ordering invalid.'}

Write-Output 'MAGIRECO_COSTUME_SWITCH_SOURCE_INTEGRATION_APPLIED'
