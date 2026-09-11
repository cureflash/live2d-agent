[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d{6}$')]
    [string]$CharacterId
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

try {
    $base=Join-Path $env:LOCALAPPDATA 'live2d-agent'
    $statePath=Join-Path $base ('magireco-character-'+$CharacterId+'.json')
    if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw 'CHARACTER_EXTRACTION_STATE_NOT_FOUND'}
    $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json
    $voiceSource=[IO.Path]::GetFullPath([string]$state.VoiceDirectory)
    if(-not(Test-Path -LiteralPath $voiceSource -PathType Container)){throw 'VOICE_SOURCE_DIRECTORY_NOT_FOUND'}

    $modulePath=Join-Path $PSScriptRoot 'LocalPcmWave.psm1'
    if(-not(Test-Path -LiteralPath $modulePath -PathType Leaf)){throw 'LOCAL_PCM_MODULE_NOT_FOUND'}
    Import-Module $modulePath -Force

    $tools=Join-Path $base 'tools'
    $decoderRoot=Join-Path $tools 'vgmstream-r2117'
    $decoder=Join-Path $decoderRoot 'vgmstream-cli.exe'
    if(-not(Test-Path -LiteralPath $decoder -PathType Leaf)){
        $null=New-Item -ItemType Directory -Path $decoderRoot -Force
        $zip=Join-Path $decoderRoot 'vgmstream-win64.zip'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/vgmstream/vgmstream/releases/download/r2117/vgmstream-win64.zip' -OutFile $zip
        $expected='6c4a8a3813864fefed081bbd337dbc0ad93bf88e0b92f5db98d7ab258b22dc6c'
        if((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected){throw 'DECODER_ARCHIVE_CHECKSUM_MISMATCH'}
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $unpack=Join-Path $decoderRoot 'unpacked'
        if(Test-Path -LiteralPath $unpack){Remove-Item -LiteralPath $unpack -Recurse -Force}
        [IO.Compression.ZipFile]::ExtractToDirectory($zip,$unpack)
        $found=@(Get-ChildItem -LiteralPath $unpack -Recurse -File -Filter 'vgmstream-cli.exe')
        if($found.Count -ne 1){throw 'DECODER_CLI_NOT_UNIQUE'}
        Copy-Item -LiteralPath $found[0].FullName -Destination $decoder -Force
        foreach($dll in @(Get-ChildItem -LiteralPath $found[0].DirectoryName -File -Filter '*.dll')){
            Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $decoderRoot $dll.Name) -Force
        }
    }

    $sources=@(Get-ChildItem -LiteralPath $voiceSource -File -Filter '*.hca'|Sort-Object Name)
    if($sources.Count -eq 0){throw 'NO_HCA_VOICES_EXTRACTED'}
    $waveDir=Join-Path ([string]$state.AssetRoot) 'voice-wav'
    $null=New-Item -ItemType Directory -Path $waveDir -Force

    $clips=New-Object 'System.Collections.Generic.List[object]'
    foreach($source in $sources){
        $name=[IO.Path]::GetFileNameWithoutExtension($source.Name)
        $wave=Join-Path $waveDir ($name+'.wav')
        $process=New-Object Diagnostics.Process
        $process.StartInfo.FileName=$decoder
        $process.StartInfo.Arguments='-i -W 1 -o "'+$wave+'" "'+$source.FullName+'"'
        $process.StartInfo.WorkingDirectory=$decoderRoot
        $process.StartInfo.UseShellExecute=$false
        $process.StartInfo.RedirectStandardOutput=$true
        $process.StartInfo.RedirectStandardError=$true
        if(-not $process.Start()){throw ('DECODER_START_FAILED '+$source.Name)}
        $out=$process.StandardOutput.ReadToEndAsync()
        $err=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(30000)){$process.Kill();throw ('DECODER_TIMEOUT '+$source.Name)}
        $log=$out.Result+$err.Result
        if($process.ExitCode -ne 0){throw ('HCA_DECODE_FAILED '+$source.Name+' '+$log)}
        $process.Dispose()
        $info=Get-LocalPcmWaveInfo $wave
        $clips.Add([pscustomobject]@{
            Name=$name
            SourcePath=$source.FullName
            WavePath=$wave
            Seconds=$info.Seconds
            Channels=$info.Channels
            SampleRate=$info.SampleRate
            SourceSHA256=(Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
            WaveSHA256=(Get-FileHash -LiteralPath $wave -Algorithm SHA256).Hash
        })
    }

    $clipArray=$clips.ToArray()
    $bank=[ordered]@{
        Kind='magireco_private_character_voice_bank'
        CharacterId=$CharacterId
        AssetRoot=[string]$state.AssetRoot
        VoiceDirectory=$waveDir
        Decoder='vgmstream r2117 win64'
        Clips=$clipArray
        DecodedUtc=[DateTime]::UtcNow.ToString('o')
        CeVIOAccessed=$false
        UploadedToGitHub=$false
    }
    $bankPath=Join-Path $base ('magireco-character-'+$CharacterId+'-voice-bank.json')
    [IO.File]::WriteAllText($bankPath,($bank|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path ([string]$state.AssetRoot) 'voice-bank.json'),($bank|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))

    [ordered]@{
        Kind=$bank.Kind
        CharacterId=$CharacterId
        DecodedCount=$clipArray.Count
        Decoder=$bank.Decoder
        CeVIOAccessed=$false
        UploadedToGitHub=$false
    }|ConvertTo-Json
}
catch {
    Write-Output ('MAGIRECO_CHARACTER_VOICE_DECODE_FAILED '+$_.Exception.Message.Replace($env:USERPROFILE,'<user>'))
    exit 1
}
