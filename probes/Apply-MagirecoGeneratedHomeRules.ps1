[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$HeaderPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Replace-Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $first=$Text.IndexOf($Old,[StringComparison]::Ordinal)
    if($first -lt 0){throw ('Expected marker not found: '+$Label)}
    $second=$Text.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal)
    if($second -ge 0){throw ('Marker not unique: '+$Label)}
    return $Text.Substring(0,$first)+$New+$Text.Substring($first+$Old.Length)
}

$text=[IO.File]::ReadAllText($HeaderPath).Replace("`r`n","`n")
$text=Replace-Once $text @'
    Profile _profile = Profile::Madoka;
'@ @'
    Profile _profile = Profile::Madoka;
    std::string _voicePrefix = "vo_char_2001_00";
'@ 'voice prefix member'

$text=Replace-Once $text @'
    int StartupIndex() const
    {
        const AgentHomeSequence* seq = Sequences();
        const int count = SequenceCount();
        for (int i = 0; i < count; ++i) if (seq[i].Group == 16) return i;
        return 0;
    }
'@ @'
    int FindVoiceIndex(int voice) const
    {
        const AgentHomeSequence* seq = Sequences();
        const int count = SequenceCount();
        for (int i = 0; i < count; ++i) if (seq[i].Voice == voice) return i;
        return -1;
    }
    int TimeLoginVoice() const
    {
        SYSTEMTIME local = {};
        GetLocalTime(&local);
        const int hour = static_cast<int>(local.wHour);
        if (hour >= 5 && hour < 11) return 25;
        if (hour >= 11 && hour < 16) return 26;
        if (hour >= 16 && hour < 22) return 27;
        if (hour >= 22 || hour < 4) return 28;
        return 29;
    }
    int StartupIndex() const
    {
        static bool madokaSeen = false;
        static bool haregiSeen = false;
        bool* seen = _profile == Profile::HaregiMadoka ? &haregiSeen : &madokaSeen;
        const int wanted = *seen ? TimeLoginVoice() : 24;
        *seen = true;
        const int selected = FindVoiceIndex(wanted);
        if (selected >= 0) return selected;
        const int fallback = FindVoiceIndex(24);
        return fallback >= 0 ? fallback : 0;
    }
    int RandomTapIndex(ULONGLONG now)
    {
        int candidates[9] = {};
        int candidateCount = 0;
        for (int voice = 33; voice <= 41; ++voice)
        {
            const int index = FindVoiceIndex(voice);
            if (index >= 0) candidates[candidateCount++] = index;
        }
        if (candidateCount == 0) return -1;
        ++_tapSerial;
        return candidates[static_cast<int>((now + static_cast<ULONGLONG>(_tapSerial) * 2654435761ULL) % static_cast<ULONGLONG>(candidateCount))];
    }
'@ 'login and tap rules'

$text=Replace-Once $text @'
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
'@ @'
    void Configure(const char* modelHomeDir)
    {
        const std::string path = modelHomeDir != nullptr ? std::string(modelHomeDir) : std::string();
        _profile = path.find("haregi") != std::string::npos ? Profile::HaregiMadoka : Profile::Madoka;
        if (_profile == Profile::HaregiMadoka)
        {
            _voicePrefix = "vo_char_2100_00";
        }
        else if (path.find("swimsuit18") != std::string::npos && GetFileAttributesA("home-audio/vo_char_2001_51_24.wav") != INVALID_FILE_ATTRIBUTES)
        {
            _voicePrefix = "vo_char_2001_51";
        }
        else if (path.find("sleepwear") != std::string::npos && GetFileAttributesA("home-audio/vo_char_2001_52_24.wav") != INVALID_FILE_ATTRIBUTES)
        {
            _voicePrefix = "vo_char_2001_52";
        }
        else if (path.find("valentine18") != std::string::npos && GetFileAttributesA("home-audio/vo_char_2001_50_24.wav") != INVALID_FILE_ATTRIBUTES)
        {
            _voicePrefix = "vo_char_2001_50";
        }
        else
        {
            _voicePrefix = "vo_char_2001_00";
        }
        ResetForProfile();
    }
    const char* VoicePrefix() const { return _voicePrefix.c_str(); }
'@ 'costume voice prefix rules'

$text=Replace-Once $text @'
                _tapPending = false; ++_tapSerial;
                const int count = SequenceCount();
                const int startup = StartupIndex();
                if (count <= 1) return false;
                int pick = static_cast<int>((now + static_cast<ULONGLONG>(_tapSerial) * 2654435761ULL) % static_cast<ULONGLONG>(count - 1));
                if (pick >= startup) ++pick;
                Begin(pick, now);
'@ @'
                _tapPending = false;
                const int pick = RandomTapIndex(now);
                if (pick < 0) return false;
                Begin(pick, now);
'@ 'tap selection'

# Normalize generated float literals such as 99f to valid C++ floating literals.
$text=[regex]::Replace($text,'(?<![\d\.])(\d+)f\b','$1.0f')
[IO.File]::WriteAllText($HeaderPath,$text,(New-Object Text.UTF8Encoding($true)))

$check=[IO.File]::ReadAllText($HeaderPath)
if(-not $check.Contains('for (int voice = 33; voice <= 41; ++voice)')){throw 'Tap range 33..41 missing.'}
if(-not $check.Contains('return 25;')){throw 'Time login routing missing.'}
if(-not $check.Contains('vo_char_2001_51')){throw 'Swimsuit voice prefix missing.'}
if(-not $check.Contains('vo_char_2001_52')){throw 'Sleepwear voice prefix missing.'}
Write-Output 'MAGIRECO_GENERATED_HOME_RULES_APPLIED'
Write-Output 'login=24,time=25-29,ap=30,bp=31,unused=32,tap=33-41,battle_start=42'
