[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Normalized([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Source file missing: $Path" }
    return [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
}

function Replace-ExactlyOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $first = $Text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Expected source marker not found: $Label" }
    $second = $Text.IndexOf($Old, $first + $Old.Length, [StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Source marker is not unique: $Label" }
    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

function Replace-LineOnce([string]$Text, [string]$Prefix, [string]$New, [string]$Label) {
    $pattern = '(?m)^' + [regex]::Escape($Prefix) + '[^\n]*\n'
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -ne 1) { throw "Expected exactly one source line: $Label count=$($matches.Count)" }
    $match = $matches[0]
    return $Text.Substring(0, $match.Index) + $New + $Text.Substring($match.Index + $match.Length)
}

function Write-SourceUtf8Bom([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($true)))
}

$source = [IO.Path]::GetFullPath($SourceRoot)
$hppPath = Join-Path $source 'LAppModel.hpp'
$cppPath = Join-Path $source 'LAppModel.cpp'
$managerPath = Join-Path $source 'LAppLive2DManager.cpp'

$hpp = Read-Normalized $hppPath
$hpp = Replace-ExactlyOnce $hpp @'
#include "AgentExpression.hpp"


/**
'@ @'
#include "AgentExpression.hpp"

class AgentHome;

/**
'@ 'LAppModel.hpp AgentHome forward declaration'
$hpp = Replace-ExactlyOnce $hpp @'
    AgentAudio _agentAudio;
    AgentExpression _agentExpression;
public:
'@ @'
    AgentAudio _agentAudio;
    AgentExpression _agentExpression;
    AgentHome* _agentHome;
public:
'@ 'LAppModel.hpp members'
$hpp = Replace-ExactlyOnce $hpp @'
    virtual Csm::csmBool HitTest(const Csm::csmChar* hitAreaName, Csm::csmFloat32 x, Csm::csmFloat32 y);
'@ @'
    virtual Csm::csmBool HitTest(const Csm::csmChar* hitAreaName, Csm::csmFloat32 x, Csm::csmFloat32 y);
    void StartHomeTap();
'@ 'LAppModel.hpp StartHomeTap declaration'
Write-SourceUtf8Bom $hppPath $hpp

$cpp = Read-Normalized $cppPath
$cpp = Replace-ExactlyOnce $cpp @'
#include "LAppModel.hpp"
'@ @'
#include "LAppModel.hpp"
#include "AgentHome.hpp"
'@ 'LAppModel.cpp AgentHome include'
$cpp = Replace-ExactlyOnce $cpp @'
LAppModel::LAppModel()
    : LAppModel_Common()
'@ @'
LAppModel::LAppModel()
    : LAppModel_Common()
    , _agentHome(new AgentHome())
'@ 'LAppModel.cpp AgentHome construction'
$cpp = Replace-ExactlyOnce $cpp @'
LAppModel::~LAppModel()
{
'@ @'
LAppModel::~LAppModel()
{
    delete _agentHome;
    _agentHome = NULL;
'@ 'LAppModel.cpp AgentHome destruction'
$cpp = Replace-LineOnce $cpp '    _model->LoadParameters();' @'
    _model->LoadParameters();

    AgentHomeAction homeAction;
    if (_agentHome->Poll(homeAction))
    {
        if (homeAction.Voice >= 0)
        {
            const std::string number = homeAction.Voice < 10
                ? std::string("0") + std::to_string(homeAction.Voice)
                : std::to_string(homeAction.Voice);
            const std::string voicePath = std::string("home-audio/vo_char_2001_00_") + number + ".wav";
            if (!_agentAudio.QueueLocalWave(voicePath))
            {
                LAppPal::PrintLogLn("[APP]home voice queue rejected: [%s]", voicePath.c_str());
            }
        }
        if (homeAction.Motion >= 0)
        {
            const std::string motionName = homeAction.Motion == 0
                ? std::string("motion_000.motion3.json")
                : std::string("motion_") + std::to_string(homeAction.Motion) + ".motion3.json";
            const csmInt32 motionCount = _modelSetting->GetMotionCount("Motion");
            for (csmInt32 i = 0; i < motionCount; ++i)
            {
                const csmChar* fileName = _modelSetting->GetMotionFileName("Motion", i);
                if (fileName != NULL && std::string(fileName).find(motionName) != std::string::npos)
                {
                    StartMotion("Motion", i, PriorityForce);
                    break;
                }
            }
        }
        if (homeAction.Expression != nullptr)
        {
            const std::string expressionName = std::string(homeAction.Expression) + ".exp3.json";
            SetExpression(expressionName.c_str());
        }
    }

'@ 'LAppModel.cpp home dispatcher'
$cpp = Replace-ExactlyOnce $cpp @'
        StartRandomMotion(MotionGroupIdle, PriorityIdle);
'@ @'
        if (!_agentHome->IsActive()) StartRandomMotion(MotionGroupIdle, PriorityIdle);
'@ 'LAppModel.cpp idle suppression'
$cpp = Replace-ExactlyOnce $cpp @'
CubismMotionQueueEntryHandle LAppModel::StartMotion(const csmChar* group, csmInt32 no, csmInt32 priority,
'@ @'
void LAppModel::StartHomeTap()
{
    if (!_agentAudio.IsBusy()) _agentHome->RequestTap();
}

CubismMotionQueueEntryHandle LAppModel::StartMotion(const csmChar* group, csmInt32 no, csmInt32 priority,
'@ 'LAppModel.cpp StartHomeTap implementation'
Write-SourceUtf8Bom $cppPath $cpp

$manager = Read-Normalized $managerPath
$manager = Replace-ExactlyOnce $manager @'
        if (_models[i]->HitTest(HitAreaNameHead, x, y))
'@ @'
        if (true)
'@ 'LAppLive2DManager.cpp bypass broken hit-area names'
$manager = Replace-ExactlyOnce $manager @'
            _models[i]->SetRandomExpression();
'@ @'
            _models[i]->StartHomeTap();
'@ 'LAppLive2DManager.cpp head tap'
$manager = Replace-ExactlyOnce $manager @'
            _models[i]->StartRandomMotion(MotionGroupTapBody, PriorityNormal, FinishedMotion, BeganMotion);
'@ @'
            _models[i]->StartHomeTap();
'@ 'LAppLive2DManager.cpp body tap'
Write-SourceUtf8Bom $managerPath $manager

$hppCheck = Read-Normalized $hppPath
$cppCheck = Read-Normalized $cppPath
$managerCheck = Read-Normalized $managerPath
if (-not $hppCheck.Contains('class AgentHome;')) { throw 'AgentHome forward declaration missing after edit.' }
if (-not $hppCheck.Contains('AgentHome* _agentHome;')) { throw 'AgentHome pointer missing after edit.' }
if ($hppCheck.Contains('#include "AgentHome.hpp"')) { throw 'AgentHome implementation leaked into public model header.' }
if (-not $hppCheck.Contains('void StartHomeTap();')) { throw 'StartHomeTap declaration missing after edit.' }
if (-not $cppCheck.Contains('#include "AgentHome.hpp"')) { throw 'AgentHome implementation include missing in cpp.' }
if (-not $cppCheck.Contains('_agentAudio.QueueLocalWave(voicePath)')) { throw 'Home audio dispatch missing after edit.' }
if (-not $cppCheck.Contains('expressionName = std::string(homeAction.Expression) + ".exp3.json"')) { throw 'Home expression-name mapping missing.' }
if (-not $cppCheck.Contains('if (!_agentHome->IsActive()) StartRandomMotion(MotionGroupIdle, PriorityIdle);')) { throw 'Home idle suppression missing after edit.' }
if ($cppCheck.Contains('_agentHome->ApplyOverrides(_model);')) { throw 'Unverified cheek/tear override remains enabled.' }
if (-not $managerCheck.Contains('        if (true)')) { throw 'Broken hit-area gate was not bypassed.' }
if (($managerCheck.Split([string[]]@('_models[i]->StartHomeTap();'), [StringSplitOptions]::None).Count - 1) -ne 2) { throw 'Expected both legacy tap actions to route home tap.' }

Write-Output 'MAGIRECO_HOME_SOURCE_INTEGRATION_APPLIED'
