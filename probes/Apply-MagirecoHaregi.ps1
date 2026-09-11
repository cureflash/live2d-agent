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
$modelCppPath=Join-Path $source 'LAppModel.cpp'
$managerCppPath=Join-Path $source 'LAppLive2DManager.cpp'
$managerHppPath=Join-Path $source 'LAppLive2DManager.hpp'
$delegateCppPath=Join-Path $source 'LAppDelegate.cpp'

$modelCpp=Read-Normalized $modelCppPath
$modelCpp=Replace-ExactlyOnce $modelCpp @'
    _modelHomeDir = dir;
'@ @'
    _modelHomeDir = dir;
    _agentHome->Configure(dir);
'@ 'LAppModel profile configuration'
$modelCpp=Replace-ExactlyOnce $modelCpp @'
            const std::string voicePath = std::string("home-audio/vo_char_2001_00_") + number + ".wav";
'@ @'
            const std::string voicePath = std::string("home-audio/") + _agentHome->VoicePrefix() + "_" + number + ".wav";
'@ 'LAppModel dynamic voice prefix'
$modelCpp=Replace-ExactlyOnce $modelCpp @'
            const std::string motionName = homeAction.Motion == 0
                ? std::string("motion_000.motion3.json")
                : std::string("motion_") + std::to_string(homeAction.Motion) + ".motion3.json";
'@ @'
            std::string motionNumber = std::to_string(homeAction.Motion);
            while (motionNumber.size() < 3) motionNumber = std::string("0") + motionNumber;
            const std::string motionName = std::string("motion_") + motionNumber + ".motion3.json";
'@ 'LAppModel zero-padded motion names'
Write-Utf8Bom $modelCppPath $modelCpp

$managerHpp=Read-Normalized $managerHppPath
$managerHpp=Replace-ExactlyOnce $managerHpp @'
    void NextScene();
'@ @'
    void NextScene();
    void NextCharacter();
'@ 'LAppLive2DManager NextCharacter declaration'
$managerHpp=Replace-ExactlyOnce $managerHpp @'
    Csm::csmInt32 _sceneIndex; ///< 表示するシーンのインデックス値
'@ @'
    Csm::csmInt32 _sceneIndex; ///< 表示するシーンのインデックス値
    Csm::csmInt32 _lastMadokaSceneIndex;
'@ 'LAppLive2DManager last Madoka costume index'
Write-Utf8Bom $managerHppPath $managerHpp

$managerCpp=Read-Normalized $managerCppPath
$managerCpp=Replace-ExactlyOnce $managerCpp @'
    int CompareCsmString(const void* a, const void* b)
    {
        return strcmp(reinterpret_cast<const Csm::csmString*>(a)->GetRawString(),
            reinterpret_cast<const Csm::csmString*>(b)->GetRawString());
    }
'@ @'
    int CompareCsmString(const void* a, const void* b)
    {
        return strcmp(reinterpret_cast<const Csm::csmString*>(a)->GetRawString(),
            reinterpret_cast<const Csm::csmString*>(b)->GetRawString());
    }

    bool IsMadokaCostumeName(const char* name)
    {
        return strcmp(name, "model") == 0 || strcmp(name, "uniform") == 0 ||
            strcmp(name, "valentine18") == 0 || strcmp(name, "swimsuit18") == 0 ||
            strcmp(name, "sleepwear") == 0;
    }
'@ 'LAppLive2DManager costume classifier'
$managerCpp=Replace-ExactlyOnce $managerCpp @'
    , _sceneIndex(0)
{
    _viewMatrix = new CubismMatrix44();
    SetUpModel();

    ChangeScene(_sceneIndex);
}
'@ @'
    , _sceneIndex(0)
    , _lastMadokaSceneIndex(0)
{
    _viewMatrix = new CubismMatrix44();
    SetUpModel();
    for (csmInt32 i = 0; i < _modelDir.GetSize(); ++i)
    {
        if (strcmp(_modelDir[i].GetRawString(), "model") == 0)
        {
            _sceneIndex = i;
            _lastMadokaSceneIndex = i;
            break;
        }
    }

    ChangeScene(_sceneIndex);
}
'@ 'LAppLive2DManager initial normal Madoka scene'
$managerCpp=Replace-ExactlyOnce $managerCpp @'
void LAppLive2DManager::NextScene()
{
    csmInt32 no = (_sceneIndex + 1) % GetModelDirSize();
    ChangeScene(no);
}

void LAppLive2DManager::ChangeScene(Csm::csmInt32 index)
'@ @'
void LAppLive2DManager::NextScene()
{
    static const char* costumes[] = {"model", "uniform", "valentine18", "swimsuit18", "sleepwear"};
    const char* current = _modelDir[_sceneIndex].GetRawString();
    int currentCostume = -1;
    for (int i = 0; i < 5; ++i)
    {
        if (strcmp(current, costumes[i]) == 0)
        {
            currentCostume = i;
            break;
        }
    }
    if (currentCostume < 0) return;
    const char* next = costumes[(currentCostume + 1) % 5];
    for (csmInt32 i = 0; i < _modelDir.GetSize(); ++i)
    {
        if (strcmp(_modelDir[i].GetRawString(), next) == 0)
        {
            ChangeScene(i);
            return;
        }
    }
}

void LAppLive2DManager::NextCharacter()
{
    if (strcmp(_modelDir[_sceneIndex].GetRawString(), "haregi") == 0)
    {
        ChangeScene(_lastMadokaSceneIndex);
        return;
    }
    for (csmInt32 i = 0; i < _modelDir.GetSize(); ++i)
    {
        if (strcmp(_modelDir[i].GetRawString(), "haregi") == 0)
        {
            ChangeScene(i);
            return;
        }
    }
}

void LAppLive2DManager::ChangeScene(Csm::csmInt32 index)
'@ 'LAppLive2DManager costume and character switching'
$managerCpp=Replace-ExactlyOnce $managerCpp @'
    const csmString& model = _modelDir[index];
'@ @'
    const csmString& model = _modelDir[index];
    if (IsMadokaCostumeName(model.GetRawString())) _lastMadokaSceneIndex = index;
'@ 'LAppLive2DManager remember costume on character switch'
Write-Utf8Bom $managerCppPath $managerCpp

$delegateCpp=Read-Normalized $delegateCppPath
$delegateCpp=Replace-ExactlyOnce $delegateCpp @'
    case WM_MOUSEMOVE:
'@ @'
    case WM_RBUTTONUP:
        if (s_instance != NULL)
        {
            LAppLive2DManager::GetInstance()->NextCharacter();
        }
        return 0;

    case WM_MOUSEMOVE:
'@ 'LAppDelegate right-click character switch'
Write-Utf8Bom $delegateCppPath $delegateCpp

$modelCheck=Read-Normalized $modelCppPath
$managerCheck=Read-Normalized $managerCppPath
$managerHppCheck=Read-Normalized $managerHppPath
$delegateCheck=Read-Normalized $delegateCppPath
if(-not $modelCheck.Contains('_agentHome->Configure(dir);')){throw 'Home profile configuration missing.'}
if(-not $modelCheck.Contains('_agentHome->VoicePrefix()')){throw 'Dynamic voice prefix missing.'}
if(-not $modelCheck.Contains('while (motionNumber.size() < 3)')){throw 'Motion zero-padding missing.'}
if(-not $managerHppCheck.Contains('void NextCharacter();')){throw 'NextCharacter declaration missing.'}
if(-not $managerCheck.Contains('IsMadokaCostumeName')){throw 'Costume classifier missing.'}
if(-not $managerCheck.Contains('strcmp(_modelDir[_sceneIndex].GetRawString(), "haregi")')){throw 'Haregi character toggle missing.'}
if(-not $delegateCheck.Contains('case WM_RBUTTONUP:')){throw 'Right-click switch route missing.'}
Write-Output 'MAGIRECO_HAREGI_SOURCE_INTEGRATION_APPLIED'
Write-Output 'character_switch=right_click costume_switch=gear'
