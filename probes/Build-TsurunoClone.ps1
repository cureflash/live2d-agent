[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$Pin
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$process=$null

function Download-RepoFile([string]$Relative,[string]$Destination) {
    $uri='https://raw.githubusercontent.com/cureflash/live2d-agent/'+$Pin+'/'+$Relative
    Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $Destination
}

try {
    $base=Join-Path $env:LOCALAPPDATA 'live2d-agent'
    $statePath=Join-Path $base 'sample-build.json'
    if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw 'SAMPLE_BUILD_STATE_NOT_FOUND'}
    $built=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not(Test-Path -LiteralPath $built.SDKRoot -PathType Container)){throw 'SDK_ROOT_NOT_FOUND'}

    $assetStatePath=Join-Path $base 'magireco-character-100300.json'
    if(-not(Test-Path -LiteralPath $assetStatePath -PathType Leaf)){throw 'TSURUNO_EXTRACTED_ASSET_STATE_NOT_FOUND'}
    $assetState=Get-Content -LiteralPath $assetStatePath -Raw -Encoding UTF8|ConvertFrom-Json
    if([string]$assetState.CharacterId -ne '100300' -or [string]$assetState.ScenarioId -ne '100300'){
        throw 'TSURUNO_EXTRACTED_ASSET_STATE_MISMATCH'
    }
    $assetRoot=[IO.Path]::GetFullPath([string]$assetState.AssetRoot)
    $sourceRoot=[IO.Path]::GetFullPath([string]$assetState.ModelDirectory)
    $configPath=[IO.Path]::GetFullPath([string]$assetState.ModelSource)
    if(-not $sourceRoot.StartsWith($assetRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'TSURUNO_MODEL_DIRECTORY_OUTSIDE_ASSET_ROOT'}
    if(-not $configPath.StartsWith($sourceRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'TSURUNO_MODEL_CONFIG_OUTSIDE_MODEL_DIRECTORY'}
    if(-not(Test-Path -LiteralPath $sourceRoot -PathType Container)){throw 'TSURUNO_MODEL_DIRECTORY_NOT_FOUND'}
    if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){throw 'TSURUNO_MODEL_CONFIG_NOT_FOUND'}
    $config=Get-Item -LiteralPath $configPath
    $model=Get-Content -LiteralPath $config.FullName -Raw -Encoding UTF8|ConvertFrom-Json
    if($model.Version -ne 3 -or -not $model.FileReferences.Moc){throw 'TSURUNO_MODEL_UNSUPPORTED'}

    $motionFiles=@()
    if($model.FileReferences.Motions.Motion){$motionFiles=@($model.FileReferences.Motions.Motion|ForEach-Object {[string]$_.File})}
    foreach($required in @('motion_000.motion3.json','motion_101.motion3.json','motion_200.motion3.json','motion_400.motion3.json')){
        if(-not($motionFiles|Where-Object {[IO.Path]::GetFileName($_) -eq $required})){
            throw ('TSURUNO_REQUIRED_MOTION_MISSING: '+$required)
        }
    }

    $runKey=if($env:GITHUB_RUN_ID){$env:GITHUB_RUN_ID}else{[guid]::NewGuid().ToString('N')}
    $work=Join-Path $base ('tsuruno-clone-build-'+$runKey)
    $relative='Samples\D3D11\Demo\proj.d3d11.cmake'
    $source=Join-Path $work $relative
    $null=New-Item -ItemType Directory -Path $source -Force
    Copy-Item -LiteralPath (Join-Path $built.SDKRoot ($relative+'\src')) -Destination $source -Recurse

    $cmakeText=Get-Content -LiteralPath (Join-Path $built.SDKRoot ($relative+'\CMakeLists.txt')) -Raw -Encoding UTF8
    $needle='set(SDK_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../../..)'
    if(-not $cmakeText.Contains($needle)){throw 'SDK_CMAKE_SOURCE_DIFFERS'}
    $cmakeText=$cmakeText.Replace($needle,('set(SDK_ROOT_PATH "'+$built.SDKRoot.Replace('\','/')+'")'))
    [IO.File]::WriteAllText((Join-Path $source 'CMakeLists.txt'),$cmakeText,(New-Object Text.UTF8Encoding($false)))

    foreach($name in @('AgentAudio.hpp','AgentExpression.hpp','AgentHomeTsuruno.hpp')){
        Download-RepoFile ('native/'+$name) (Join-Path $source ('src\'+$name))
    }
    foreach($pair in @(
        @('native/sdk-integration.patch','integration.patch'),
        @('native/expression-control.patch','expression.patch'),
        @('native/tsuruno-home-behavior.patch','tsuruno-home.patch')
    )){
        $patch=Join-Path $work $pair[1]
        Download-RepoFile $pair[0] $patch
        & git -C $work apply --check --ignore-space-change $patch
        if($LASTEXITCODE -ne 0){throw ('PATCH_CHECK_FAILED: '+$pair[0])}
        & git -C $work apply --ignore-space-change $patch
        if($LASTEXITCODE -ne 0){throw ('PATCH_APPLY_FAILED: '+$pair[0])}
    }

    $vswhere=Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio\Installer\vswhere.exe'
    $installations=@(& $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.14.44.17.14.x86.x64 -property installationPath)
    if($LASTEXITCODE -ne 0 -or $installations.Count -ne 1){throw 'V143_INSTALLATION_NOT_UNIQUE'}
    $cmake=Join-Path $installations[0] 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    $buildDir=Join-Path $work 'build'
    & $cmake -S $source -B $buildDir -G 'Visual Studio 18 2026' -A x64 -T 'v143,version=14.44.35207' *> (Join-Path $work 'configure.log')
    if($LASTEXITCODE -ne 0){throw 'TSURUNO_CONFIGURE_FAILED'}
    & $cmake --build $buildDir --config Release --parallel 2 *> (Join-Path $work 'build.log')
    if($LASTEXITCODE -ne 0){
        Get-Content -LiteralPath (Join-Path $work 'build.log')|Where-Object {$_ -match 'error [A-Z]+[0-9]+'}|ForEach-Object {([string]$_).Replace($env:USERPROFILE,'<user>')}
        throw 'TSURUNO_BUILD_FAILED'
    }

    $runtime=Join-Path $base ('tsuruno-clone-runtime-'+$runKey)
    $null=New-Item -ItemType Directory -Path $runtime -Force
    Get-ChildItem -LiteralPath $built.WorkingDirectory -File|Copy-Item -Destination $runtime
    foreach($folder in @('SampleShaders','FrameworkShaders')){
        Copy-Item -LiteralPath (Join-Path $built.WorkingDirectory $folder) -Destination $runtime -Recurse
    }
    $resources=Join-Path $runtime 'Resources'
    $null=New-Item -ItemType Directory -Path $resources -Force
    Get-ChildItem -LiteralPath (Join-Path $built.WorkingDirectory 'Resources') -File|Copy-Item -Destination $resources
    $modelTarget=Join-Path $resources 'model'
    $null=New-Item -ItemType Directory -Path $modelTarget -Force
    Get-ChildItem -LiteralPath $sourceRoot -Force|Copy-Item -Destination $modelTarget -Recurse -Force
    Copy-Item -LiteralPath $config.FullName -Destination (Join-Path $modelTarget 'model.model3.json') -Force
    Copy-Item -LiteralPath (Join-Path $buildDir 'bin\Demo\Release\Demo.exe') -Destination (Join-Path $runtime 'Demo.exe') -Force

    $process=Start-Process -FilePath (Join-Path $runtime 'Demo.exe') -WorkingDirectory $runtime -PassThru
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $windowSeen=$false
    $responsive=$false
    while($timer.Elapsed.TotalSeconds -lt 30){
        $process.Refresh()
        if($process.HasExited){break}
        if($process.MainWindowHandle -ne [IntPtr]::Zero){
            $windowSeen=$true
            $responsive=$process.Responding
            break
        }
        Start-Sleep -Milliseconds 250
    }
    if(-not $windowSeen -or -not $responsive -or $process.HasExited){throw 'TSURUNO_WINDOW_START_FAILED'}

    Start-Sleep -Seconds 18
    $process.Refresh()
    if($process.HasExited -or -not $process.Responding){throw 'TSURUNO_WINDOW_DID_NOT_STAY_RESPONSIVE'}
    $closeRequested=$process.CloseMainWindow()
    $closed=$process.WaitForExit(10000)
    if(-not $closeRequested -or -not $closed -or $process.ExitCode -ne 0){throw 'TSURUNO_WINDOW_CLOSE_FAILED'}

    [ordered]@{
        Kind='tsuruno_100300_isolated_movement_probe'
        ModelFound=$true
        RequiredMotionsFound=@('000','101','200','400')
        BuildSucceeded=$true
        WindowObserved=$windowSeen
        Responsive=$responsive
        Sequence='group_16 movement only; audio and expressions intentionally disabled'
        SourceAssetsModified=$false
        VisualMovement='requires_user_confirmation'
    }|ConvertTo-Json -Depth 4
} catch {
    Write-Output ('TSURUNO_CLONE_PROBE_FAILED '+$_.Exception.Message.Replace($env:USERPROFILE,'<user>'))
    exit 1
} finally {
    if($null -ne $process -and -not $process.HasExited){$null=$process.CloseMainWindow()}
}
