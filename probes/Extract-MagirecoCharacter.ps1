[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d{6}$')]
    [string]$CharacterId,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d{6}$')]
    [string]$ScenarioId
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$noxBin='C:\Program Files (x86)\Nox\bin'
$nox=Join-Path $noxBin 'Nox.exe'
$adb=Join-Path $noxBin 'nox_adb.exe'
$serial='127.0.0.1:62001'
$package='io.kamihama.totentanz'
$androidBase='/data/data/'+$package+'/files/madomagi'
$modelRemote=$androidBase+'/resource/image_native/live2d_v4/'+$CharacterId
$scenarioRemote=$androidBase+'/resource/scenario/json/general/'+$ScenarioId+'.json'
$voiceRemoteDir=$androidBase+'/resource/sound_native/voice'

function Test-NoxDeviceConnected {
    $devices=@(& $adb devices 2>&1)
    if($LASTEXITCODE -ne 0){return $false}
    return [bool]($devices -match ([regex]::Escape($serial)+'\s+device'))
}

function Ensure-NoxDevice {
    if(Test-NoxDeviceConnected){return}
    if(-not(Test-Path -LiteralPath $nox -PathType Leaf)){throw 'NOX_LAUNCHER_NOT_FOUND'}
    $existing=@(Get-Process -Name 'Nox' -ErrorAction SilentlyContinue)
    if($existing.Count -eq 0){
        $null=Start-Process -FilePath $nox -WorkingDirectory $noxBin -PassThru
    }
    $deadline=[DateTime]::UtcNow.AddSeconds(150)
    do {
        Start-Sleep -Seconds 2
        if(Test-NoxDeviceConnected){return}
    } while([DateTime]::UtcNow -lt $deadline)
    throw 'NOX_DEVICE_START_TIMEOUT'
}

function Invoke-Adb([string[]]$Arguments) {
    $output=@(& $adb -s $serial @Arguments 2>&1)
    if($LASTEXITCODE -ne 0){
        throw ('ADB_FAILED '+($Arguments -join ' ')+' :: '+(($output|ForEach-Object {[string]$_}) -join ' | '))
    }
    return $output
}

function Test-RemotePath([string]$Path,[switch]$Directory) {
    $test=if($Directory){'-d'}else{'-f'}
    $result=Invoke-Adb @('shell',('if [ '+$test+" '"+$Path+"' ]; then echo PRESENT; else echo MISSING; fi"))
    return (@($result|ForEach-Object {[string]$_}) -contains 'PRESENT')
}

function Get-ModelReferences($Model) {
    $refs=New-Object 'System.Collections.Generic.List[string]'
    if($Model.FileReferences.Moc){$refs.Add([string]$Model.FileReferences.Moc)}
    foreach($texture in @($Model.FileReferences.Textures)){if($texture){$refs.Add([string]$texture)}}
    foreach($key in @('Physics','Pose','UserData','DisplayInfo')){
        $value=$Model.FileReferences.$key
        if($value){$refs.Add([string]$value)}
    }
    foreach($expression in @($Model.FileReferences.Expressions)){
        if($expression.File){$refs.Add([string]$expression.File)}
    }
    if($Model.FileReferences.Motions){
        foreach($group in $Model.FileReferences.Motions.PSObject.Properties){
            foreach($motion in @($group.Value)){
                if($motion.File){$refs.Add([string]$motion.File)}
                if($motion.Sound){$refs.Add([string]$motion.Sound)}
            }
        }
    }
    return @($refs|Sort-Object -Unique)
}

$stage=$null
try {
    if(-not(Test-Path -LiteralPath $adb -PathType Leaf)){throw 'NOX_ADB_NOT_FOUND'}
    Ensure-NoxDevice

    $packages=Invoke-Adb @('shell','pm list packages')
    if(-not($packages -contains ('package:'+$package))){throw 'TOTENTANZ_PACKAGE_NOT_FOUND'}
    $identity=(Invoke-Adb @('shell','id')|ForEach-Object {[string]$_}) -join ' '
    if($identity -notmatch 'uid=0'){throw 'NOX_ADB_NOT_ROOT; private app data cannot be read through the established path'}

    if(-not(Test-RemotePath $modelRemote -Directory)){throw ('MODEL_NOT_FOUND_ON_DEVICE '+$CharacterId)}
    if(-not(Test-RemotePath $scenarioRemote)){throw ('SCENARIO_NOT_FOUND_ON_DEVICE '+$ScenarioId)}

    $base=Join-Path $env:LOCALAPPDATA 'live2d-agent'
    $assetRoot=Join-Path $base 'magireco-assets'
    $stagingRoot=Join-Path $assetRoot '.staging'
    $runKey=if($env:GITHUB_RUN_ID){$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT}else{[guid]::NewGuid().ToString('N')}
    $stage=Join-Path $stagingRoot ($CharacterId+'-'+$runKey)
    $live2d=Join-Path $stage 'live2d'
    $scenarioDir=Join-Path $stage 'scenario'
    $voiceDir=Join-Path $stage 'voice-hca'
    $null=New-Item -ItemType Directory -Path $live2d,$scenarioDir,$voiceDir -Force

    $null=Invoke-Adb @('pull',($modelRemote+'/.'),$live2d)
    $scenarioLocal=Join-Path $scenarioDir ($ScenarioId+'.json')
    $null=Invoke-Adb @('pull',$scenarioRemote,$scenarioLocal)

    $modelPath=Join-Path $live2d 'model.model3.json'
    if(-not(Test-Path -LiteralPath $modelPath -PathType Leaf)){throw 'MODEL_CONFIG_NOT_EXTRACTED'}
    $model=Get-Content -LiteralPath $modelPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($model.Version -ne 3 -or -not $model.FileReferences.Moc){throw 'MODEL_CONFIG_UNSUPPORTED'}
    $refs=Get-ModelReferences $model
    $missingRefs=New-Object 'System.Collections.Generic.List[string]'
    foreach($relative in $refs){
        $full=[IO.Path]::GetFullPath((Join-Path $live2d $relative))
        if(-not $full.StartsWith($live2d+'\',[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $full -PathType Leaf)){
            $missingRefs.Add($relative)
        }
    }
    if($missingRefs.Count -gt 0){throw ('MODEL_REFERENCES_MISSING '+($missingRefs -join ','))}

    $scenarioRaw=Get-Content -LiteralPath $scenarioLocal -Raw -Encoding UTF8
    $null=$scenarioRaw|ConvertFrom-Json
    $voiceNames=@([regex]::Matches($scenarioRaw,'"voice"\s*:\s*"(?<voice>[^"]+)"')|ForEach-Object {$_.Groups['voice'].Value}|Sort-Object -Unique)
    $voicePrefixes=@($voiceNames|ForEach-Object {if($_ -match '^vo_char_(\d{4})_'){$Matches[1]}}|Where-Object {$_}|Sort-Object -Unique)
    $remoteVoices=New-Object 'System.Collections.Generic.List[string]'
    foreach($prefix in $voicePrefixes){
        $listed=Invoke-Adb @('shell',("find '"+$voiceRemoteDir+"' -maxdepth 1 -type f -name 'vo_char_"+$prefix+"_*.hca' -print 2>/dev/null"))
        foreach($line in $listed){
            $path=([string]$line).Trim()
            if($path -and -not $remoteVoices.Contains($path)){$remoteVoices.Add($path)}
        }
    }
    foreach($remote in $remoteVoices){
        $name=[IO.Path]::GetFileName($remote)
        $null=Invoke-Adb @('pull',$remote,(Join-Path $voiceDir $name))
    }

    $modelFiles=@(Get-ChildItem -LiteralPath $live2d -Recurse -File)
    $hashLines=@($modelFiles|Sort-Object FullName|ForEach-Object {
        $rel=$_.FullName.Substring($live2d.Length).TrimStart('\')
        $rel+'|'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })
    $bytes=[Text.Encoding]::UTF8.GetBytes(($hashLines -join "`n"))
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$fingerprint=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}

    $motionCount=0
    if($model.FileReferences.Motions){
        foreach($p in $model.FileReferences.Motions.PSObject.Properties){$motionCount+=@($p.Value).Count}
    }

    $finalParent=Join-Path $assetRoot $CharacterId
    $null=New-Item -ItemType Directory -Path $finalParent -Force
    $final=Join-Path $finalParent $runKey
    if(Test-Path -LiteralPath $final){throw 'FINAL_EXTRACTION_PATH_ALREADY_EXISTS'}
    Move-Item -LiteralPath $stage -Destination $final
    $stage=$null

    $manifest=[ordered]@{
        Kind='magireco_private_character_extract'
        CharacterId=$CharacterId
        ScenarioId=$ScenarioId
        Package=$package
        Device=$serial
        AssetRoot=$final
        ModelDirectory=(Join-Path $final 'live2d')
        ModelSource=(Join-Path $final 'live2d\model.model3.json')
        ScenarioPath=(Join-Path $final ('scenario\'+$ScenarioId+'.json'))
        VoiceDirectory=(Join-Path $final 'voice-hca')
        VoicePrefixes=$voicePrefixes
        VoiceFileCount=@(Get-ChildItem -LiteralPath (Join-Path $final 'voice-hca') -File).Count
        ModelFileCount=$modelFiles.Count
        ReferencedFileCount=$refs.Count
        TextureCount=@($model.FileReferences.Textures).Count
        ExpressionCount=@($model.FileReferences.Expressions).Count
        MotionCount=$motionCount
        AssetFingerprintSHA256=$fingerprint
        ExtractedUtc=[DateTime]::UtcNow.ToString('o')
        SourceAssetsModified=$false
        UploadedToGitHub=$false
    }
    $manifestPath=Join-Path $final 'manifest.json'
    [IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
    $statePath=Join-Path $base ('magireco-character-'+$CharacterId+'.json')
    [IO.File]::WriteAllText($statePath,($manifest|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))

    [ordered]@{
        Kind=$manifest.Kind
        CharacterId=$CharacterId
        ScenarioId=$ScenarioId
        ModelFileCount=$manifest.ModelFileCount
        ReferencedFileCount=$manifest.ReferencedFileCount
        TextureCount=$manifest.TextureCount
        ExpressionCount=$manifest.ExpressionCount
        MotionCount=$manifest.MotionCount
        VoiceFileCount=$manifest.VoiceFileCount
        AssetFingerprintSHA256=$fingerprint
        SourceAssetsModified=$false
        UploadedToGitHub=$false
    }|ConvertTo-Json -Depth 5
}
catch {
    Write-Output ('MAGIRECO_CHARACTER_EXTRACT_FAILED '+$_.Exception.Message.Replace($env:USERPROFILE,'<user>'))
    exit 1
}
finally {
    if($stage -and (Test-Path -LiteralPath $stage)){
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
