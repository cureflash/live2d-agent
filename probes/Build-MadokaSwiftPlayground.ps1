[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'MadokaLive2D.swiftpm')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Replace-ExactlyOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $first = $Text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Expected source marker not found: $Label" }
    $second = $Text.IndexOf($Old, $first + $Old.Length, [StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Source marker is not unique: $Label" }
    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

function Replace-RegexOnce([string]$Text, [string]$Pattern, [string]$Replacement, [string]$Label) {
    $matches = [regex]::Matches($Text, $Pattern)
    if ($matches.Count -ne 1) { throw "Expected exactly one regex source marker: $Label count=$($matches.Count)" }
    return [regex]::Replace($Text, $Pattern, $Replacement, 1)
}

function Normalize-Lf([string]$Text) {
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-Utf8([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent) { $null = New-Item -ItemType Directory -Path $parent -Force }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Require-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label missing: $Path" }
}

$base = Join-Path $env:LOCALAPPDATA 'live2d-agent'
$homeStatePath = Join-Path $base 'magireco-home-build.json'
Require-File $homeStatePath 'Magireco home build state'
$homeState = Get-Content -LiteralPath $homeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtime = [string]$homeState.WorkingDirectory
if (-not (Test-Path -LiteralPath $runtime -PathType Container)) { throw 'Magireco home runtime directory is missing.' }

$modelSource = Join-Path $runtime 'Resources\model'
$audioSource = Join-Path $runtime 'home-audio'
$configSource = Join-Path $modelSource 'model.model3.json'
Require-File $configSource 'Madoka model3.json'
foreach ($number in @(24) + @(33..42)) {
    Require-File (Join-Path $audioSource ('vo_char_2001_00_{0:D2}.wav' -f $number)) ('Madoka voice '+$number)
}

$config = Get-Content -LiteralPath $configSource -Raw -Encoding UTF8 | ConvertFrom-Json
$motions = @($config.FileReferences.Motions.Motion)
$motionMap = [ordered]@{}
foreach ($number in @(0,100,200,300,400)) {
    $suffix = if ($number -eq 0) { '000' } else { [string]$number }
    $found = @()
    for ($i = 0; $i -lt $motions.Count; $i++) {
        if ([string]$motions[$i].File -match ('motion_' + $suffix + '\.motion3\.json$')) { $found += $i }
    }
    if ($found.Count -ne 1) { throw "Expected exactly one motion_$suffix entry in Motion group." }
    $motionMap[[string]$number] = [int]$found[0]
}

$expressions = @($config.FileReferences.Expressions)
$expressionMap = [ordered]@{}
foreach ($suffix in @('010','011','020','030','040','041','051')) {
    $found = @($expressions | Where-Object { [string]$_.File -match ('mtn_ex_' + $suffix + '\.exp3\.json$') })
    if ($found.Count -ne 1) { throw "Expected exactly one mtn_ex_$suffix expression entry." }
    $name = [string]$found[0].Name
    if ([string]::IsNullOrWhiteSpace($name)) { throw "Expression mtn_ex_$suffix has no Name." }
    $expressionMap['mtn_ex_' + $suffix] = $name
}

$runKey = if ($env:GITHUB_RUN_ID) { $env:GITHUB_RUN_ID } else { [guid]::NewGuid().ToString('N') }
$work = Join-Path $base ('swift-playgrounds-madoka-' + $runKey)
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
$null = New-Item -ItemType Directory -Path $work -Force
$sdk = Join-Path $work 'CubismWebSamples'

& git clone --quiet --depth 1 --branch '5-r.5' --recurse-submodules --shallow-submodules https://github.com/Live2D/CubismWebSamples.git $sdk
if ($LASTEXITCODE -ne 0) { throw 'Failed to clone Live2D/CubismWebSamples 5-r.5.' }

$demo = Join-Path $sdk 'Samples\TypeScript\Demo'
$demoSrc = Join-Path $demo 'src'
$resources = Join-Path $sdk 'Samples\Resources'
$madokaDir = Join-Path $resources 'Madoka'
if (Test-Path -LiteralPath $madokaDir) { Remove-Item -LiteralPath $madokaDir -Recurse -Force }
Copy-Item -LiteralPath $modelSource -Destination $madokaDir -Recurse
Rename-Item -LiteralPath (Join-Path $madokaDir 'model.model3.json') -NewName 'Madoka.model3.json'
$homeAudioDir = Join-Path $madokaDir 'home-audio'
$null = New-Item -ItemType Directory -Path $homeAudioDir -Force
foreach ($number in @(24) + @(33..42)) {
    Copy-Item -LiteralPath (Join-Path $audioSource ('vo_char_2001_00_{0:D2}.wav' -f $number)) -Destination $homeAudioDir -Force
}

$homeConfig = [ordered]@{
    motionIndices = $motionMap
    expressionNames = $expressionMap
    generatedUtc = [DateTime]::UtcNow.ToString('o')
}
Write-Utf8 (Join-Path $madokaDir 'home-config.json') ($homeConfig | ConvertTo-Json -Depth 20)

$lappDefinePath = Join-Path $demoSrc 'lappdefine.ts'
$lappDefine = Normalize-Lf (Get-Content -LiteralPath $lappDefinePath -Raw -Encoding UTF8)
$lappDefine = Replace-ExactlyOnce $lappDefine "export const ResourcesPath = '../../Resources/';" "export const ResourcesPath = './Resources/';" 'ResourcesPath'
$lappDefine = Replace-RegexOnce $lappDefine '(?s)export const ModelDir: string\[\] = \[.*?\];' "export const ModelDir: string[] = [`n  'Madoka'`n];" 'ModelDir'
Write-Utf8 $lappDefinePath $lappDefine

$vitePath = Join-Path $demo 'vite.config.mts'
$vite = Normalize-Lf (Get-Content -LiteralPath $vitePath -Raw -Encoding UTF8)
$vite = Replace-ExactlyOnce $vite "    base: '/'," "    base: './'," 'Vite relative base'
Write-Utf8 $vitePath $vite

$indexPath = Join-Path $demo 'index.html'
$index = Normalize-Lf (Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8)
$index = Replace-ExactlyOnce $index './Core/live2dcubismcore.js' './Core/live2dcubismcore.min.js' 'Cubism Core script'
$index = Replace-ExactlyOnce $index '<title>TypeScript HTML App</title>' '<title>Madoka Live2D</title>' 'HTML title'
Write-Utf8 $indexPath $index

$lappModelPath = Join-Path $demoSrc 'lappmodel.ts'
$lappModel = Normalize-Lf (Get-Content -LiteralPath $lappModelPath -Raw -Encoding UTF8)
$lappModel = Replace-ExactlyOnce $lappModel 'export class LAppModel extends CubismUserModel {' @'
export class LAppModel extends CubismUserModel {
  private _homeActive = false;

  public setHomeActive(active: boolean): void {
    this._homeActive = active;
  }

  public isHomeReady(): boolean {
    return this._state === LoadStep.CompleteSetup;
  }

  public startHomeVoice(filePath: string): void {
    this._wavFileHandler.start(filePath);
  }
'@ 'LAppModel home API'
$lappModel = Replace-ExactlyOnce $lappModel 'if (this._motionManager.isFinished()) {' 'if (this._motionManager.isFinished() && !this._homeActive) {' 'Idle suppression while home sequence is active'
Write-Utf8 $lappModelPath $lappModel

$homeTs = @'
import * as LAppDefine from './lappdefine';
import { LAppModel } from './lappmodel';

type Scene = { seconds: number; motion: number; expression: string | null };
type Sequence = { voice: number; scenes: Scene[] };
type HomeConfig = {
  motionIndices: Record<string, number>;
  expressionNames: Record<string, string>;
};

const sequences: Sequence[] = [
  { voice: 24, scenes: [
    { seconds: 1.0, motion: 100, expression: 'mtn_ex_010' },
    { seconds: 1.0, motion: -1, expression: 'mtn_ex_011' },
    { seconds: 4.0, motion: 0, expression: 'mtn_ex_010' },
    { seconds: 1.5, motion: -1, expression: 'mtn_ex_011' },
    { seconds: 5.0, motion: 100, expression: 'mtn_ex_010' }
  ]},
  { voice: 33, scenes: [
    { seconds: 1.0, motion: 0, expression: 'mtn_ex_040' },
    { seconds: 2.0, motion: -1, expression: 'mtn_ex_041' },
    { seconds: 3.0, motion: 100, expression: 'mtn_ex_040' },
    { seconds: 3.0, motion: 300, expression: 'mtn_ex_020' },
    { seconds: 2.0, motion: -1, expression: 'mtn_ex_030' },
    { seconds: 4.0, motion: 0, expression: 'mtn_ex_040' }
  ]},
  { voice: 34, scenes: [
    { seconds: 1.0, motion: 100, expression: 'mtn_ex_011' },
    { seconds: 3.0, motion: 0, expression: 'mtn_ex_010' },
    { seconds: 2.0, motion: -1, expression: 'mtn_ex_011' },
    { seconds: 2.0, motion: 300, expression: 'mtn_ex_010' },
    { seconds: 2.0, motion: -1, expression: 'mtn_ex_011' },
    { seconds: 2.0, motion: 100, expression: 'mtn_ex_010' },
    { seconds: 2.0, motion: -1, expression: 'mtn_ex_041' }
  ]},
  { voice: 35, scenes: [
    { seconds: 4.0, motion: 0, expression: 'mtn_ex_030' },
    { seconds: 4.0, motion: 100, expression: 'mtn_ex_040' },
    { seconds: 1.0, motion: 0, expression: 'mtn_ex_041' },
    { seconds: 5.0, motion: -1, expression: 'mtn_ex_010' }
  ]},
  { voice: 36, scenes: [
    { seconds: 4.0, motion: 0, expression: 'mtn_ex_051' },
    { seconds: 4.0, motion: 300, expression: 'mtn_ex_030' },
    { seconds: 4.0, motion: 100, expression: 'mtn_ex_010' }
  ]},
  { voice: 37, scenes: [
    { seconds: 4.0, motion: 0, expression: 'mtn_ex_040' },
    { seconds: 4.0, motion: 300, expression: 'mtn_ex_030' },
    { seconds: 6.0, motion: 200, expression: 'mtn_ex_020' },
    { seconds: 3.0, motion: 0, expression: 'mtn_ex_010' }
  ]},
  { voice: 38, scenes: [
    { seconds: 5.0, motion: 0, expression: 'mtn_ex_040' },
    { seconds: 2.0, motion: -1, expression: 'mtn_ex_030' },
    { seconds: 6.0, motion: 100, expression: 'mtn_ex_010' },
    { seconds: 4.0, motion: -1, expression: 'mtn_ex_011' }
  ]},
  { voice: 39, scenes: [
    { seconds: 2.0, motion: 0, expression: 'mtn_ex_010' },
    { seconds: 3.0, motion: 100, expression: null },
    { seconds: 6.0, motion: 300, expression: 'mtn_ex_011' }
  ]},
  { voice: 40, scenes: [
    { seconds: 3.0, motion: 100, expression: 'mtn_ex_051' },
    { seconds: 3.5, motion: 300, expression: 'mtn_ex_040' },
    { seconds: 7.0, motion: 0, expression: 'mtn_ex_051' }
  ]},
  { voice: 41, scenes: [
    { seconds: 2.0, motion: 0, expression: 'mtn_ex_051' },
    { seconds: 3.0, motion: -1, expression: 'mtn_ex_030' },
    { seconds: 2.0, motion: 300, expression: 'mtn_ex_040' },
    { seconds: 3.0, motion: -1, expression: 'mtn_ex_051' },
    { seconds: 4.0, motion: 0, expression: 'mtn_ex_030' }
  ]},
  { voice: 42, scenes: [
    { seconds: 1.0, motion: 200, expression: 'mtn_ex_020' }
  ]}
];

const delay = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));

export class MadokaHome {
  private _config: HomeConfig | null = null;
  private _token = 0;
  private _tapSerial = 0;
  private _audio: HTMLAudioElement | null = null;
  private _ready: Promise<LAppModel | null> | null = null;

  public start(getModel: () => LAppModel): void {
    if (this._ready) return;
    this._ready = this.prepare(getModel);
    void this._ready.then(async model => {
      if (!model) return;
      await delay(500);
      if (this._tapSerial === 0) await this.runSequence(0, model);
    });
  }

  public requestTap(model: LAppModel): void {
    ++this._tapSerial;
    const serial = this._tapSerial;
    const run = async (target: LAppModel | null) => {
      if (!target || !this._config) return;
      const now = Math.floor(performance.now());
      const index = 1 + ((now + serial * 2654435761) % 10);
      await this.runSequence(index, target);
    };
    if (this._ready) void this._ready.then(run);
    else void run(model);
  }

  private async prepare(getModel: () => LAppModel): Promise<LAppModel | null> {
    const response = await fetch(`${LAppDefine.ResourcesPath}Madoka/home-config.json`);
    if (!response.ok) throw new Error('Madoka home config load failed.');
    this._config = (await response.json()) as HomeConfig;
    for (let i = 0; i < 200; i++) {
      const model = getModel();
      if (model && model.isHomeReady()) return model;
      await delay(50);
    }
    return null;
  }

  private stopAudio(): void {
    if (!this._audio) return;
    this._audio.pause();
    this._audio.currentTime = 0;
    this._audio = null;
  }

  private async runSequence(index: number, model: LAppModel): Promise<void> {
    if (!this._config) return;
    const sequence = sequences[index];
    if (!sequence) return;

    const token = ++this._token;
    this.stopAudio();
    model.setHomeActive(true);

    const voiceName = `vo_char_2001_00_${sequence.voice.toString().padStart(2, '0')}.wav`;
    const voicePath = `${LAppDefine.ResourcesPath}Madoka/home-audio/${voiceName}`;
    model.startHomeVoice(voicePath);
    this._audio = new Audio(voicePath);
    this._audio.preload = 'auto';
    try { await this._audio.play(); } catch (error) { console.warn('Madoka voice playback failed', error); }

    for (const scene of sequence.scenes) {
      if (token !== this._token) return;
      if (scene.motion >= 0) {
        const motionIndex = this._config.motionIndices[String(scene.motion)];
        if (Number.isInteger(motionIndex)) {
          model.startMotion('Motion', motionIndex, LAppDefine.PriorityForce);
        }
      }
      if (scene.expression) {
        const expressionName = this._config.expressionNames[scene.expression];
        if (expressionName) model.setExpression(expressionName);
      }
      await delay(scene.seconds * 1000);
    }

    if (token === this._token) model.setHomeActive(false);
  }
}
'@
Write-Utf8 (Join-Path $demoSrc 'madokahome.ts') $homeTs

$managerPath = Join-Path $demoSrc 'lapplive2dmanager.ts'
$manager = Normalize-Lf (Get-Content -LiteralPath $managerPath -Raw -Encoding UTF8)
$manager = Replace-ExactlyOnce $manager "import { LAppSubdelegate } from './lappsubdelegate';" "import { LAppSubdelegate } from './lappsubdelegate';`nimport { MadokaHome } from './madokahome';" 'MadokaHome import'

$tapStartMarker = '  public onTap(x: number, y: number): void {'
$tapStart = $manager.IndexOf($tapStartMarker, [StringComparison]::Ordinal)
if ($tapStart -lt 0) { throw 'Madoka tap method start marker missing.' }
if ($manager.IndexOf($tapStartMarker, $tapStart + $tapStartMarker.Length, [StringComparison]::Ordinal) -ge 0) { throw 'Madoka tap method start marker is not unique.' }
$nextComment = $manager.IndexOf('  /**', $tapStart + $tapStartMarker.Length, [StringComparison]::Ordinal)
$updateStart = $manager.IndexOf('  public onUpdate(): void {', $tapStart + $tapStartMarker.Length, [StringComparison]::Ordinal)
if ($nextComment -lt 0 -or $updateStart -lt 0 -or $nextComment -gt $updateStart) { throw 'Madoka tap method end markers are invalid.' }
$tapReplacement = @'
  public onTap(x: number, y: number): void {
    if (LAppDefine.DebugLogEnable) {
      LAppPal.printMessage(`[APP]tap point: {x: ${x.toFixed(2)} y: ${y.toFixed(2)}}`);
    }
    const model: LAppModel = this._models[0];
    if (model) this._madokaHome.requestTap(model);
  }

'@
$manager = $manager.Substring(0, $tapStart) + $tapReplacement + $manager.Substring($nextComment)
$manager = Replace-ExactlyOnce $manager '    this._sceneIndex = 0;' "    this._sceneIndex = 0;`n    this._madokaHome = new MadokaHome();" 'MadokaHome construction'
$manager = Replace-ExactlyOnce $manager '    this._subdelegate = subdelegate;' "    this._subdelegate = subdelegate;`n    this._madokaHome.start(() => this._models[0]);" 'MadokaHome startup'
$manager = Replace-RegexOnce $manager '(?m)^  private _sceneIndex: number;.*$' "  private _sceneIndex: number;`n  private _madokaHome: MadokaHome;" 'MadokaHome field'
Write-Utf8 $managerPath $manager

Push-Location $demo
try {
    & npm ci --silent
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed for Cubism Web sample.' }
    & npm run build:prod
    if ($LASTEXITCODE -ne 0) { throw 'Cubism Web production build failed.' }
} finally {
    Pop-Location
}

$dist = Join-Path $demo 'dist'
Require-File (Join-Path $dist 'index.html') 'Cubism Web dist index'
$coreDir = Join-Path $dist 'Core'
$null = New-Item -ItemType Directory -Path $coreDir -Force
Invoke-WebRequest -UseBasicParsing -Uri 'https://cubism.live2d.com/sdk-web/cubismcore/live2dcubismcore.min.js' -OutFile (Join-Path $coreDir 'live2dcubismcore.min.js')
Require-File (Join-Path $coreDir 'live2dcubismcore.min.js') 'Cubism Core for Web'

if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Recurse -Force }
$appModule = Join-Path $OutputPath 'Sources\AppModule'
$webOutput = Join-Path $appModule 'Resources\Web'
$null = New-Item -ItemType Directory -Path $webOutput -Force
Copy-Item -Path (Join-Path $dist '*') -Destination $webOutput -Recurse -Force
Require-File (Join-Path $webOutput 'index.html') 'Swift Playgrounds Web index'
Require-File (Join-Path $webOutput 'Core\live2dcubismcore.min.js') 'Swift Playgrounds Cubism Core'
Require-File (Join-Path $webOutput 'Resources\Madoka\Madoka.model3.json') 'Swift Playgrounds Madoka model'

$packageSwift = @'
// swift-tools-version: 5.10
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "MadokaLive2D",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "MadokaLive2D",
            targets: ["AppModule"],
            bundleIdentifier: "local.cureflash.MadokaLive2D",
            displayVersion: "1.0",
            bundleVersion: "1",
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [.portrait, .landscapeRight, .landscapeLeft]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources/AppModule",
            resources: [.process("Resources")]
        )
    ]
)
'@
Write-Utf8 (Join-Path $OutputPath 'Package.swift') $packageSwift

$appSwift = @'
import SwiftUI
import WebKit

@main
struct MadokaLive2DApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    var body: some View {
        MadokaWebView()
            .ignoresSafeArea()
            .background(Color.black)
    }
}

struct MadokaWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false

        guard let resourceURL = Bundle.module.resourceURL else {
            fatalError("Swift package resources are unavailable.")
        }
        let webRoot = resourceURL.appendingPathComponent("Web", isDirectory: true)
        let indexURL = webRoot.appendingPathComponent("index.html")
        view.loadFileURL(indexURL, allowingReadAccessTo: webRoot)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
'@
Write-Utf8 (Join-Path $appModule 'MadokaLive2DApp.swift') $appSwift

$state = [ordered]@{
    Kind = 'madoka_swift_playgrounds_ready'
    OutputPath = $OutputPath
    CubismWebSamples = '5-r.5'
    CubismCoreSource = 'https://cubism.live2d.com/sdk-web/cubismcore/live2dcubismcore.min.js'
    ModelSource = $modelSource
    VoiceCount = 11
    PrivateAssetsRemainLocal = $true
    GeneratedUtc = [DateTime]::UtcNow.ToString('o')
}
Write-Utf8 (Join-Path $base 'madoka-swift-playgrounds.json') ($state | ConvertTo-Json -Depth 10)

Write-Output ('MADOKA_SWIFT_PLAYGROUNDS_READY output=' + $OutputPath)
Write-Output 'renderer=SwiftUI+WKWebView+CubismWeb startup_voice=24 tap_voices=33-42 motions=true expressions=true pose=true lipsync=true'