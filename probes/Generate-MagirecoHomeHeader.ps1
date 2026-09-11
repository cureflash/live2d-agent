[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$MadokaScenarioPath,
    [Parameter(Mandatory=$true)][string]$HaregiScenarioPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$culture=[Globalization.CultureInfo]::InvariantCulture

function Get-Optional($Object,[string]$Name){
    if($null -eq $Object){return $null}
    $p=$Object.PSObject.Properties[$Name]
    if($null -eq $p){return $null}
    return $p.Value
}

function Get-ScenarioGroups([string]$Path,[string]$Tag){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw ('Scenario missing: '+$Path)}
    $json=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $records=New-Object 'System.Collections.Generic.List[object]'
    foreach($property in $json.story.PSObject.Properties){
        if($property.Name -notmatch '^group_(\d+)$'){continue}
        $group=[int]$Matches[1]
        $items=@($property.Value)
        $voiceNumber=$null
        $scenes=New-Object 'System.Collections.Generic.List[object]'
        foreach($item in $items){
            $chars=@(Get-Optional $item 'chara')
            if($chars.Count -eq 0 -or $null -eq $chars[0]){continue}
            $c=$chars[0]
            $clear=Get-Optional $c 'textHomeStatus'
            if([string]$clear -eq 'Clear'){continue}
            $voice=[string](Get-Optional $c 'voice')
            if($voice -and $voice -match '_(\d+)$'){
                if($null -eq $voiceNumber){$voiceNumber=[int]$Matches[1]}
            }
            $secValue=Get-Optional $item 'autoTurnFirst'
            $seconds=if($null -eq $secValue){0.1}else{[double]$secValue}
            if($seconds -lt 0.05){$seconds=0.05}
            $motionValue=Get-Optional $c 'motion'
            $motion=if($null -eq $motionValue){-1}else{[int]$motionValue}
            $face=[string](Get-Optional $c 'face')
            if($face){$face=$face -replace '\.exp3?\.json$',''}
            $cheekValue=Get-Optional $c 'cheek'
            $tearValue=Get-Optional $c 'tear'
            $cheek=if($null -eq $cheekValue){99.0}else{[double]$cheekValue}
            $tear=if($null -eq $tearValue){99.0}else{[double]$tearValue}
            $scenes.Add([pscustomobject]@{Seconds=$seconds;Motion=$motion;Expression=$face;Cheek=$cheek;Tear=$tear})
        }
        if($null -ne $voiceNumber -and $scenes.Count -gt 0){
            $records.Add([pscustomobject]@{Tag=$Tag;Group=$group;Voice=$voiceNumber;Scenes=$scenes.ToArray()})
        }
    }
    return @($records.ToArray() | Sort-Object Group)
}

function F([double]$Value){return $Value.ToString('0.###',$culture)+'f'}
function D([double]$Value){return $Value.ToString('0.###',$culture)}

$madoka=Get-ScenarioGroups $MadokaScenarioPath 'madoka'
$haregi=Get-ScenarioGroups $HaregiScenarioPath 'haregi'
if($madoka.Count -lt 2){throw 'Too few Madoka home groups.'}
if($haregi.Count -lt 2){throw 'Too few Haregi home groups.'}

$sb=New-Object Text.StringBuilder
$null=$sb.AppendLine('#pragma once')
$null=$sb.AppendLine('#include <windows.h>')
$null=$sb.AppendLine('#include <cstddef>')
$null=$sb.AppendLine('#include <string>')
$null=$sb.AppendLine('#include <CubismFramework.hpp>')
$null=$sb.AppendLine('#include <Id/CubismIdManager.hpp>')
$null=$sb.AppendLine('#include <Model/CubismModel.hpp>')
$null=$sb.AppendLine('')
$null=$sb.AppendLine('struct AgentHomeScene { double Seconds; int Motion; const char* Expression; float Cheek; float Tear; };')
$null=$sb.AppendLine('struct AgentHomeSequence { int Group; int Voice; const AgentHomeScene* Scenes; std::size_t Count; };')
$null=$sb.AppendLine('struct AgentHomeAction { int Voice; int Motion; const char* Expression; };')
$null=$sb.AppendLine('')

foreach($profile in @([pscustomobject]@{Name='madoka';Records=$madoka},[pscustomobject]@{Name='haregi';Records=$haregi})){
    foreach($r in $profile.Records){
        $arrayName='agent_'+$profile.Name+'_g'+$r.Group
        $null=$sb.AppendLine(('static const AgentHomeScene '+$arrayName+'[] = {'))
        foreach($s in $r.Scenes){
            $expr=if([string]::IsNullOrEmpty([string]$s.Expression)){'nullptr'}else{'"'+([string]$s.Expression).Replace('"','\"')+'"'}
            $null=$sb.AppendLine(('    {'+(D $s.Seconds)+', '+$s.Motion+', '+$expr+', '+(F $s.Cheek)+', '+(F $s.Tear)+'},'))
        }
        $null=$sb.AppendLine('};')
    }
    $seqName='agent_'+$profile.Name+'_sequences'
    $null=$sb.AppendLine(('static const AgentHomeSequence '+$seqName+'[] = {'))
    foreach($r in $profile.Records){
        $arrayName='agent_'+$profile.Name+'_g'+$r.Group
        $null=$sb.AppendLine(('    {'+$r.Group+', '+$r.Voice+', '+$arrayName+', sizeof('+$arrayName+') / sizeof('+$arrayName+'[0])},'))
    }
    $null=$sb.AppendLine('};')
    $null=$sb.AppendLine('')
}

$null=$sb.AppendLine(@'
class AgentHome
{
    static constexpr float Keep = 99.0f;
    enum class Profile { Madoka, HaregiMadoka };
    Profile _profile = Profile::Madoka;
    bool _startupPending = true;
    bool _tapPending = false;
    bool _active = false;
    bool _emitPending = false;
    bool _voicePending = false;
    bool _cheekSet = false;
    bool _tearSet = false;
    bool _resetTearPending = false;
    float _cheek = 0.0f;
    float _tear = 0.0f;
    int _sequenceIndex = -1;
    std::size_t _sceneIndex = 0;
    unsigned _tapSerial = 0;
    ULONGLONG _bootAt = GetTickCount64() + 500;
    ULONGLONG _sceneStarted = 0;

    const AgentHomeSequence* Sequences() const
    {
        return _profile == Profile::HaregiMadoka ? agent_haregi_sequences : agent_madoka_sequences;
    }
    int SequenceCount() const
    {
        return _profile == Profile::HaregiMadoka
            ? static_cast<int>(sizeof(agent_haregi_sequences) / sizeof(agent_haregi_sequences[0]))
            : static_cast<int>(sizeof(agent_madoka_sequences) / sizeof(agent_madoka_sequences[0]));
    }
    int StartupIndex() const
    {
        const AgentHomeSequence* seq = Sequences();
        const int count = SequenceCount();
        for (int i = 0; i < count; ++i) if (seq[i].Group == 16) return i;
        return 0;
    }
    const AgentHomeSequence& Sequence(int index) const { return Sequences()[index]; }

    void ResetForProfile()
    {
        _startupPending = true; _tapPending = false; _active = false; _emitPending = false; _voicePending = false;
        _cheekSet = false; _tearSet = false; _resetTearPending = false; _sequenceIndex = -1; _sceneIndex = 0;
        _bootAt = GetTickCount64() + 500; _sceneStarted = 0;
    }
    void ApplySceneState(const AgentHomeScene& scene)
    {
        if (scene.Cheek != Keep) { _cheek = scene.Cheek; _cheekSet = true; }
        if (scene.Tear != Keep) { _tear = scene.Tear; _tearSet = true; }
    }
    void Begin(int sequenceIndex, ULONGLONG now)
    {
        _sequenceIndex = sequenceIndex; _sceneIndex = 0; _sceneStarted = now; _active = true; _emitPending = true;
        _voicePending = true; _resetTearPending = false; _tearSet = false;
        ApplySceneState(Sequence(_sequenceIndex).Scenes[_sceneIndex]);
    }
    static void SetParameter(Live2D::Cubism::Framework::CubismModel* model, const char* name, float value)
    {
        using namespace Live2D::Cubism::Framework;
        CubismIdHandle target = CubismFramework::GetIdManager()->GetId(name);
        for (int i = 0; i < model->GetParameterCount(); ++i)
        {
            if (model->GetParameterId(i) == target) { model->SetParameterValue(i, value); return; }
        }
    }

public:
    void Configure(const char* modelHomeDir)
    {
        const std::string path = modelHomeDir != nullptr ? std::string(modelHomeDir) : std::string();
        _profile = path.find("haregi") != std::string::npos ? Profile::HaregiMadoka : Profile::Madoka;
        ResetForProfile();
    }
    const char* VoicePrefix() const
    {
        return _profile == Profile::HaregiMadoka ? "vo_char_2100_00" : "vo_char_2001_00";
    }
    bool IsActive() const { return _active || _startupPending || _tapPending; }
    bool RequestTap()
    {
        _startupPending = false; _active = false; _emitPending = false; _voicePending = false; _sceneIndex = 0;
        _sequenceIndex = -1; _cheekSet = false; _tearSet = false; _resetTearPending = true; _tapPending = true;
        return true;
    }
    bool Poll(AgentHomeAction& action)
    {
        action = {-1, -1, nullptr};
        const ULONGLONG now = GetTickCount64();
        if (!_active)
        {
            if (_startupPending && now >= _bootAt)
            {
                _startupPending = false; Begin(StartupIndex(), now);
            }
            else if (_tapPending)
            {
                _tapPending = false; ++_tapSerial;
                const int count = SequenceCount();
                const int startup = StartupIndex();
                if (count <= 1) return false;
                int pick = static_cast<int>((now + static_cast<ULONGLONG>(_tapSerial) * 2654435761ULL) % static_cast<ULONGLONG>(count - 1));
                if (pick >= startup) ++pick;
                Begin(pick, now);
            }
            else return false;
        }
        const AgentHomeSequence& sequence = Sequence(_sequenceIndex);
        if (!_emitPending)
        {
            while (_active)
            {
                const AgentHomeScene& current = sequence.Scenes[_sceneIndex];
                const ULONGLONG durationMs = static_cast<ULONGLONG>(current.Seconds * 1000.0 + 0.5);
                if (now - _sceneStarted < durationMs) return false;
                _sceneStarted += durationMs; ++_sceneIndex;
                if (_sceneIndex >= sequence.Count)
                {
                    _active = false; _cheekSet = false;
                    if (_tearSet) { _tearSet = false; _resetTearPending = true; }
                    return false;
                }
                ApplySceneState(sequence.Scenes[_sceneIndex]); _emitPending = true; break;
            }
        }
        if (!_emitPending) return false;
        const AgentHomeScene& scene = sequence.Scenes[_sceneIndex];
        action.Voice = _voicePending ? sequence.Voice : -1; action.Motion = scene.Motion; action.Expression = scene.Expression;
        _voicePending = false; _emitPending = false; return true;
    }
    void ApplyOverrides(Live2D::Cubism::Framework::CubismModel* model)
    {
        if (_active)
        {
            if (_cheekSet) SetParameter(model, "ParamCheek", _cheek);
            if (_tearSet) SetParameter(model, "ParamTear", _tear);
        }
        else if (_resetTearPending)
        {
            SetParameter(model, "ParamTear", 0.0f); _resetTearPending = false;
        }
    }
};
'@)

$dir=Split-Path -Parent $OutputPath
if($dir -and -not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force | Out-Null}
[IO.File]::WriteAllText($OutputPath,$sb.ToString(),(New-Object Text.UTF8Encoding($true)))
Write-Output ('MAGIRECO_HOME_HEADER_GENERATED madoka_groups='+$madoka.Count+' haregi_groups='+$haregi.Count+' output='+$OutputPath)
