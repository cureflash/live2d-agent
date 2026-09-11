[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$Pin
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Download-RepoFile([string]$Relative,[string]$Destination) {
    $uri='https://raw.githubusercontent.com/cureflash/live2d-agent/'+$Pin+'/'+$Relative
    Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $Destination
}

$base=Join-Path $env:LOCALAPPDATA 'live2d-agent'
$built=Get-Content -LiteralPath (Join-Path $base 'sample-build.json') -Raw -Encoding UTF8|ConvertFrom-Json
$private=Get-Content -LiteralPath (Join-Path $base 'private-model.json') -Raw -Encoding UTF8|ConvertFrom-Json
$bank=Get-Content -LiteralPath (Join-Path $base 'madoka-voice-bank.json') -Raw -Encoding UTF8|ConvertFrom-Json
$runKey=if($env:GITHUB_RUN_ID){$env:GITHUB_RUN_ID}else{[guid]::NewGuid().ToString('N')}
$work=Join-Path $base ('magireco-home-build-'+$runKey)
$relative='Samples\D3D11\Demo\proj.d3d11.cmake'
$source=Join-Path $work $relative
$null=New-Item -ItemType Directory -Path $source
Copy-Item -LiteralPath (Join-Path $built.SDKRoot ($relative+'\src')) -Destination $source -Recurse

$cmakeText=Get-Content -LiteralPath (Join-Path $built.SDKRoot ($relative+'\CMakeLists.txt')) -Raw -Encoding UTF8
$needle='set(SDK_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../../..)'
if(-not $cmakeText.Contains($needle)){throw 'SDK CMake source differs.'}
$cmakeText=$cmakeText.Replace($needle,('set(SDK_ROOT_PATH "'+$built.SDKRoot.Replace('\','/')+'")'))
[IO.File]::WriteAllText((Join-Path $source 'CMakeLists.txt'),$cmakeText,(New-Object Text.UTF8Encoding($false)))

foreach($name in @('AgentAudio.hpp','AgentExpression.hpp','AgentHome.hpp')){
    Download-RepoFile ('native/'+$name) (Join-Path $source ('src\'+$name))
}
foreach($pair in @(
    @('native/sdk-integration.patch','integration.patch'),
    @('native/expression-control.patch','expression.patch')
)){
    $remote=$pair[0]
    $local=Join-Path $work $pair[1]
    Download-RepoFile $remote $local
    & git -C $work apply --check --ignore-space-change $local
    if($LASTEXITCODE -ne 0){throw ('Source patch mismatch: '+$remote)}
    & git -C $work apply --ignore-space-change $local
    if($LASTEXITCODE -ne 0){throw ('Source patch failed: '+$remote)}
}

$homeApply=Join-Path $work 'Apply-MagirecoHome.ps1'
Download-RepoFile 'probes/Apply-MagirecoHome.ps1' $homeApply
$tokens=$null;$parseErrors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($homeApply,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count -gt 0){throw 'Home integration script parser rejected source.'}
& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $homeApply -SourceRoot (Join-Path $source 'src')
if($LASTEXITCODE -ne 0){throw 'Home source integration failed.'}

$homeRefs=@(Get-ChildItem -LiteralPath (Join-Path $source 'src') -File|Where-Object {$_.Extension -in @('.cpp','.hpp')}|Select-String -Pattern 'StartHomeTap|AgentHome')
if($homeRefs.Count -lt 3){throw 'Home integration references missing after direct integration.'}

$vswhere=Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio\Installer\vswhere.exe'
$installations=@(& $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.14.44.17.14.x86.x64 -property installationPath)
if($LASTEXITCODE -ne 0 -or $installations.Count -ne 1){throw 'Expected one v143 installation.'}
$cmake=Join-Path $installations[0] 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$buildDir=Join-Path $work 'build'
& $cmake -S $source -B $buildDir -G 'Visual Studio 18 2026' -A x64 -T 'v143,version=14.44.35207' *> (Join-Path $work 'configure.log')
if($LASTEXITCODE -ne 0){Get-Content (Join-Path $work 'configure.log') -Tail 80;throw 'Configure failed.'}
& $cmake --build $buildDir --config Release --parallel 2 *> (Join-Path $work 'build.log')
if($LASTEXITCODE -ne 0){
    Get-Content -LiteralPath (Join-Path $work 'build.log')|Where-Object {$_ -match 'error [A-Z]+[0-9]+'}|ForEach-Object {([string]$_).Replace($env:USERPROFILE,'<user>')}
    throw 'Build failed.'
}

$runtime=Join-Path $base ('magireco-home-runtime-'+$runKey)
Copy-Item -LiteralPath $private.WorkingDirectory -Destination $runtime -Recurse
Copy-Item -LiteralPath (Join-Path $buildDir 'bin\Demo\Release\Demo.exe') -Destination (Join-Path $runtime 'Demo.exe') -Force
$modelDir=Join-Path $runtime 'Resources\model'
$configPath=Join-Path $modelDir 'model.model3.json'
$config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json
$motion0=@($config.FileReferences.Motions.Motion|Where-Object {[string]$_.File -match 'motion_000\.motion3\.json$'})
if($motion0.Count -ne 1){throw 'Expected exactly one motion_000 entry.'}
$config.FileReferences.Motions|Add-Member -MemberType NoteProperty -Name Idle -Value @([pscustomobject]@{File=[string]$motion0[0].File}) -Force
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding($false)))

$tools=Join-Path $base ('magireco-home-tools-'+$runKey)
$null=New-Item -ItemType Directory -Path $tools
foreach($name in @('CubismJsonImport.psm1','LocalPcmWave.psm1','Start-MagirecoHome.ps1')){
    Download-RepoFile ('probes/'+$name) (Join-Path $tools $name)
}
Import-Module (Join-Path $tools 'CubismJsonImport.psm1') -Force
Import-Module (Join-Path $tools 'LocalPcmWave.psm1') -Force
Convert-PrivateModelJson $modelDir

foreach($number in @(0,100,200,300,400)){
    $suffix=if($number -eq 0){'000'}else{[string]$number}
    if(-not(Test-Path -LiteralPath (Join-Path $modelDir ('mtn\motion_'+$suffix+'.motion3.json')))){throw ('Required motion missing: '+$suffix)}
}
foreach($expression in @('010','011','020','030','040','041','051')){
    if(-not(Test-Path -LiteralPath (Join-Path $modelDir ('exp\mtn_ex_'+$expression+'.exp3.json')))){throw ('Required expression missing: '+$expression)}
}
if(-not(Test-Path -LiteralPath (Join-Path $modelDir ([string]$config.FileReferences.Pose)))){throw 'Pose file missing.'}

$audioDir=Join-Path $runtime 'home-audio'
$null=New-Item -ItemType Directory -Path $audioDir
foreach($number in (@(24)+@(33..41))){
    $name=('vo_char_2001_00_{0:D2}' -f $number)
    $matches=@($bank.Clips|Where-Object {[string]$_.Name -eq $name})
    if($matches.Count -ne 1){throw ('Expected one local clip: '+$name)}
    $wave=[string]$matches[0].WavePath
    $null=Get-LocalPcmWaveInfo $wave
    Copy-Item -LiteralPath $wave -Destination (Join-Path $audioDir ($name+'.wav')) -Force
}
$speechDir=Join-Path $runtime 'speech'
$null=New-Item -ItemType Directory -Path $speechDir -Force
Remove-Item -LiteralPath (Join-Path $runtime 'speech.ready') -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $speechDir -File -ErrorAction SilentlyContinue|Remove-Item -Force

[ordered]@{
    Executable=(Join-Path $runtime 'Demo.exe')
    WorkingDirectory=$runtime
    BuildRoot=$work
    Pin=$Pin
    InstalledUtc=[DateTime]::UtcNow.ToString('o')
}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $base 'magireco-home-build.json') -Encoding UTF8

$p=New-Object Diagnostics.Process
$p.StartInfo.FileName=Join-Path $runtime 'Demo.exe'
$p.StartInfo.WorkingDirectory=$runtime
$p.StartInfo.UseShellExecute=$false
$p.StartInfo.RedirectStandardOutput=$true
$p.StartInfo.RedirectStandardError=$true
if(-not $p.Start()){throw 'Home renderer smoke failed to start.'}
$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
$ready=[Diagnostics.Stopwatch]::StartNew()
do{
    Start-Sleep -Milliseconds 250
    $p.Refresh()
    if($p.HasExited){throw 'Home renderer exited before readiness.'}
    if($ready.Elapsed.TotalSeconds -gt 60){throw 'Home renderer readiness timeout.'}
}until($p.MainWindowHandle -ne 0 -and $p.Responding)

$smoke=[Diagnostics.Stopwatch]::StartNew()
$completed=$false
do{
    Start-Sleep -Milliseconds 200
    $p.Refresh()
    if($p.HasExited){throw 'Home renderer exited during startup sequence.'}
    foreach($status in @(Get-ChildItem -LiteralPath $speechDir -File -Filter '*.status' -ErrorAction SilentlyContinue)){
        try {
            $stream=[IO.File]::Open($status.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            $reader=New-Object IO.StreamReader($stream)
            try {$text=$reader.ReadToEnd()} finally {$reader.Dispose()}
            if($text -match 'playback_completed'){$completed=$true;break}
        } catch {}
    }
    if($smoke.Elapsed.TotalSeconds -gt 35){throw 'Startup voice did not complete.'}
}until($completed -and $smoke.Elapsed.TotalSeconds -ge 13)

if(-not $p.CloseMainWindow() -or -not $p.WaitForExit(10000) -or $p.ExitCode -ne 0){throw 'Home renderer did not close normally after smoke.'}
[IO.File]::WriteAllText((Join-Path $runtime 'home-smoke.log'),($stdout.Result+$stderr.Result))

@(
    '@echo off',
    ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $tools 'Start-MagirecoHome.ps1')+'"'),
    'pause'
)|Set-Content -LiteralPath (Join-Path $base 'Launch-MagirecoHome.cmd') -Encoding Default

Write-Output ('MAGIRECO_HOME_READY runtime='+$runtime)
Write-Output 'startup_voice=24 tap_voices=33-41 pose=true expressions=true cevio=false'
