# live2d-agent

Windows上のLive2Dキャラクターが、Web版ChatGPTとCodexの作業進捗をCeVIO CS7のさとうささら音声で知らせる私的利用向け試作。

## 状態

2026-09-10: 初期仕様と検証用コード。CS7単体の音素取得・WAV合成・聴取を実機確認。常駐アプリ、遠隔受信、Live2D表示・同期は未実装・未検証。

## 確定要件

- このWeb版ChatGPTとCodexを対象とし、調査中・実装中・検証中・完了などの途中報告も通知する。最終回答だけに限定しない。
- 作業するAI自身が短いささら口調の発話文を生成。事実、確度、未検証事項を維持し、回答全文・コード・ログ・非公開内部思考は読み上げない。追加GPT APIを前提にしない。
- Windowsの最前面ウィンドウ。公式Cubism SDKと自作制御。待機・呼吸・まばたき・口パク・表情・モデルにある動作とクリック反応を対象にする。
- 発話は最後まで読み、未再生の古い通知を最新へ置換する。複数作業とタップの競合規則は未定。
- CS7は他作業優先。手動一時停止を許容。他アプリのCeVIOを終了・再起動しない。
- 一方向連携が初期版。双方向、透明化、クリック透過、視線追従、複数キャラ、既存動画アプリ統合を先回りして実装しない。
- 通常の送信から発話開始まで約10秒は暫定目標。文章生成・再生待ち・手動停止・初回起動・遠隔遅延を分離して測る。
- まどかは手元の私的仮モデル。モデル固有IDを本体へ埋め込まない。最終ささらモデル制作は別工程として検証する。

## 現在の阻害要因

ユーザー実機の出力でCS7 64bit 7.0.23と外部連携DLL 2.1.4.0、仮モデルのmoc3とmodel3.json参照先37ファイルの存在を確認。Cubism SDK for Native 5-r.5のZIP構成は確認済み。付属D3D11サンプルのCMake構成は実機のMSVC 19.51を非対応として停止。Editorの所在、モデルの描画互換性は未確認。CS7単体の音声再生は確認済み。このチャットからGitHubのワークフロー作成→Windows専用ランナーの調査ジョブ実行→ログ取得を確認済み。常駐アプリへの進捗通知配送とは別の検証。Linuxの検証をWindows成功と扱わない。以前ビューアに読み込めたというユーザー報告は、今回の公式SDK統合の証拠ではない。

## 構成案（未確定）

作業AI → 送信アダプター → データ配送 → Windows対話セッション常駐アプリ → CS7合成ワーカー／Cubism描画。

Native SDKを使うC++表示部と.NET Framework 4.8 x64のCS7連携ワーカーの分離を候補とする。ランナージョブからGUIの常駐を成立させようとしない。配送はGitHubまたは専用MCPを検証し、Web版とCodexを別判定する。このWorkで使えるツールを他のWeb画面でも使えるとは仮定しない。

GitHubリポジトリはコード用。公開リポジトリへ実際の進捗本文を配送する仕様は未承認。通信試験は個人情報のない固定短文を候補とし、実運用の非公開配送先・認証を確認してから設定する。

## 配送・同期設計の論点

ID、送信元、作業ID、送信元セッション、順序、期限、本文と許可済み表情・動作キーを持つデータ契約を作る。同ID再送は同じ指令とし、内容不一致はエラー。任意コードやシェルへ接続しない。

送信成功、Windows受付、合成成功、再生開始、再生完了を分ける。未再生の合成結果も置換対象。永続的な重複台帳と本文保存は分ける。クラッシュ時の再生結果不明を成功扱いしない。再実行方針は未確定。

WAVと音素時刻は同じ文章・読み・声設定で作る。実際の再生位置を同期基準にする。口・表情・モーションのパラメータ競合はモデル別に所有者を決めて解消する。終了・停止・失敗時の口閉じを実機確認する。

## 検証コード

- `probes/single-stream.mjs`: 単一プロセス・単一ストリームの発話順序だけを表す実行仕様。音声再生はしない。メモリ内のID台帳は検証専用で、常駐運用・再起動対応には使わない。
- `tests/single-stream.test.mjs`: A読了後にBを飛ばしてC、重複、ID衝突、古い完了イベント、不正入力を検証。Linuxで4テスト成功。
- `probes/Find-WindowsAssets.ps1`: インストール済みアプリの登録情報とDesktop/Documents/Downloads内のモデル候補を読み取る。Nox内部の操作、アプリ起動停止、設定変更、認証変更、外部送信はしない。ユーザーのWindows PowerShell 5.1 x64・対話セッションで実行成功。初期版の自動変数 $Matches との衝突を修正済み。候補がなくても不存在とはしない。出力にはローカルパスが含まれるため公開Gitへ登録しない。

テスト: `node --test tests/single-stream.test.mjs`

Windows調査はスクリプトを確認してから、保存先でWindows PowerShellを開き実行する:

```powershell
& '.\\probes\\Find-WindowsAssets.ps1'
```

実行ポリシーに阻止された場合は変更せず、エラー内容を確認する。その他の場所は任意引数 `-AdditionalModelRoots` で指定できる。Nox内にしか素材がない場合は、既存エクスポートの所在から確認し、APK解析を再開しない。

## 未確定事項

タップ範囲・セリフ・連打・発話競合、複数作業を全体一枠にするか、停止／スリープ／再起動後の扱い、期限、中断・失敗・結果不明時の再実行、一時停止の即時性、比較映像と品質合格条件、モデル制作環境、通知操作の承認頻度。設定・認証・ランナー変更は実施前に確認する。

## 次の受入検証

1. Windowsの素材・依存ソフトの場所とモデル形式を確認。
2. 最終回答前に短文1件を送信しWindows側で同ID受付を記録。同ID再送も確認。Web版とCodexを別試験にする。
3. CS7単体でWAV・音素時刻・再生、ワーカー終了後に他作業へ利用を譲れるか確認。CeVIO本体は終了しない。
4. 公式SDKで指定モデル、最前面、待機・表情・動作、欠落時エラーを確認。
5. 個別成功後に統合し、実測遅延、口パク、通知置換、通信失敗・再起動・一時停止、確定後のタップ動作を検証。

## 公式資料と公開範囲

- [CS7外部連携](https://cevio.jp/guide/cevio_cs7/interface/): 同時利用1アプリ。
- [CS7 .NET](https://cevio.jp/guide/cevio_cs7/interface/dotnet/): .NET Framework 4.8、CS7の64bit DLL、WAVと音素API。DLL無許可再配布不可。
- [Cubism 2.1との差](https://docs.live2d.com/en/cubism-sdk-manual/changefrom21/): 旧moc/mtnとmoc3/motion3.jsonは互換ではない。手元でmoc3とmodel3.jsonの存在を確認。公式SDKでの再生は未検証。
- [OpenAI developer mode](https://developers.openai.com/api/docs/guides/developer-mode): MCP書込と確認設定。実アカウントでの利用可否・途中通知は未検証。
- [Codex JSONL](https://learn.chatgpt.com/docs/non-interactive-mode): CLIイベント。Web版へは一般化しない。
- [Live2D公開条件](https://www.live2d.com/en/sdk/license/)、[CeVIO素材条件](https://cevio.jp/cevio_character/): 自作コードとSDK・モデル・素材・音声の条件は別。公式ファンキットを無条件に改変素材へ使わない。

このリポジトリには自作コード・文書のみを置く。モデル、ゲーム素材、SDK/CS7バイナリ、音声、認証情報、実進捗本文、個人環境ログは同梱しない。


## CS7単体検証（Windowsで合成・聴取確認済み）

`probes/Test-CeVIO.ps1` はCS7の公式.NET APIで同一文章・同一Talker設定から音素とWAVを生成し、SoundPlayerで再生する検証用スクリプト。常駐アプリの同期再生エンジンではない。設定変更・他アプリの終了・CeVIO本体の終了は行わないが、StartHostでCeVIOが起動する場合がある。

CeVIOを他の仕事に使っていない時だけ、別の64bit Windows PowerShell 5.1プロセスで実行する。`-CeVIOIsFree` はユーザーによる空き確認であり、自動的な占有検出ではない。DLLパスはローカルで確認した実ファイルを指定する。

```powershell
powershell.exe -NoProfile -File '.\probes\Test-CeVIO.ps1' -DllPath '<CS7 DLLのフルパス>' -Cast 'さとうささら' -Text '音声の確認をしているよ。' -CeVIOIsFree
```

WAVは一意な名前でユーザーの一時フォルダに残す。固定検証文だけを使い、WAVや実機出力を公開Gitへ登録しない。音素はメモリ内のみ。終了コード1は失敗で、失敗した段階を表示する。音が聞こえたかはユーザー確認が必要。外部連携の解放は、子PowerShell終了後に別の仕事で利用できるかを別途確認する。ホスト起動APIの所要時間には既存ホストへの接続も含まれ、コールドスタートと断定しない。

`ProbeToPlaybackCallMs` はプローブ開始から再生API呼出しまで。実際の音声出力開始、通知配送、AI生成、再生待ち、一時停止時間を測った値ではない。修正版でWindowsのAPI実行・ユーザーによる聴取を確認済み。統合動作・他アプリへの利用譲渡は未検証。

## 検証済み事項（2026-09-10）

- ユーザー提示の実機出力: PowerShell 5.1 x64、対話セッション、CS7登録情報とDLLの存在。
- 仮モデル: 設定の参照先37件すべて存在（moc3、テクスチャ3、Physics/Pose、表情22、モーション9）。内容の妥当性、内部パラメータ・当たり判定ID、見た目・動作は未検証。
- このChatGPTセッションからGitHubへのコード書込みは成功。途中通知のWindows受信を実証したものではない。Web版・CodexからWindowsへの通知経路はどちらも未検証。


### CS7実機結果（2026-09-10、ユーザー提示JSONと聴取報告）

対象は `6186e8da4a83dbffdf2c3818a52e89ff4cd7b792` の `probes/Test-CeVIO.ps1`。DLL 2.1.4.0の実機リフレクションでコンストラクターが省略可能な文字列cast引数を取ることを確認し、PowerShellのNew-Objectへ明示的にキャスト名を渡す修正後に成功。

| 項目 | 結果 |
|---|---|
| WAV合成 | API成功 |
| 音素取得 | 26件、421 ms |
| WAV合成所要時間 | 96 ms |
| StartHost呼出し | 10 ms（初回起動実測とは扱わない） |
| プローブ開始→再生API呼出し | 647 ms |
| 再生 | PlaySync復帰、ユーザーがささらの声を聴取 |
| 実音声開始時刻 | 未計測 |
| CeVIO本体の終了 | 実施せず |
| 子プロセス終了後の他アプリ利用 | 未検証 |

単発の単体試験。647 msを通知送信から発話開始までの遅延や通常時の代表値とは扱わない。JSONのAudiblePlaybackは固定の確認待ち表記であり、聴取成功は別途ユーザー報告に基づく。ローカルWAVパス・音声ファイルは公開記録へ含めない。


## GitHub経由のWindows環境調査（2026-09-10）

- [初回実行](https://github.com/cureflash/live2d-agent/actions/runs/34451779956): commit `f2edca64ab66024f9166359424a623ae86a3674e`、調査ジョブ成功。
- [追加確認](https://github.com/cureflash/live2d-agent/actions/runs/34451908168): commit `9c8ba7106ea33f34ce6e66ab68e8f5cced615a71`、調査ジョブ成功。
- ワークフロー: `.github/workflows/windows-environment-probe.yml`。main上の当該ファイルのpushと手動起動が対象。実行条件は所有者actor・対象リポジトリ・mainに限定。PR起動なし。専用ラベル `live2d-agent` に配送。
- CeVIOのDLL読込み・API接続・起動・合成・再生・終了なし。他作業優先の指示に従い音声検証を保留。
- PowerShell 5.1 x64、UserInteractive=true、SessionId=1を実ジョブで確認。表示ウィンドウ・音声出力先を確認したわけではない。
- Visual Studio登録バージョン18.9.12112.369、isComplete=true、C++ツール登録1件、Visual Studio付属CMakeファイル1件。CMakeはPATH上にない。GitとNodeはPATH上に存在。コンパイルは未実行。
- Desktop/Documents/Downloads内のLive2DCubismCore.hは0件。ただしDirectoryNotFoundExceptionが6件あり、探索は不完全。SDK未導入と断定しない。エラー発生箇所と原因、探索範囲外のSDK・Editor所在は未確認。
- ファイル内容・モデル素材・私的パスを公開する処理や成果物アップロードは追加していない。公開ログへの検査出力は環境フラグ・バージョン・件数・例外型に限定（Actions自身の標準ログは別）。
- このWebチャットで最終回答前にGitHub経由の調査ジョブを実行できた。Codex個別の送信試験、発話通知の受信・重複防止・遅延・統合動作は未検証。

### SDK所在・探索エラーの追加調査（2026-09-10）

- [切り分け実行](https://github.com/cureflash/live2d-agent/actions/runs/34455202918): 以前の6件はすべて存在する非ReparsePointフォルダー。パス長241/244文字、検索名を連結すると260/263文字。各場所で長い完全ファイル名Filterは1件の例外、短い `*` Filterは例外0件で列挙成功。列挙後の完全名照合でもCoreヘッダー0件。削除や権限変更ではなく、検索文字列の長さに依存する探索側の問題と切り分けた。OS内部の実装までは未検証。
- 修正: 短い `*Cubism*` Filterで列挙後、Nameを `Live2DCubismCore.h` と照合。Windows設定、実行ポリシー、既存アプリは変更していない。
- [修正後実行](https://github.com/cureflash/live2d-agent/actions/runs/34455318445): commit `1af7874aff5ee698518780cbfbf4e16f3cdaac52`。ヘッダー・追加候補検索・レジストリ検索のエラーはすべて0件。Coreヘッダー、指定名のNativeライブラリ・SDK ZIP・Editor実行ファイル候補は0件。Live2D/Cubismのアプリ登録、Program Files等直下の該当名フォルダーも0件。
- 範囲: Desktop/Documents/Downloadsの非隠しファイル、アンインストール登録、Program Files・Program Files(x86)・LocalAppData/Programs直下のLive2D/Cubism名フォルダー。別ドライブ・改名ZIP・隠し領域・Nox内部等は対象外。PC全体でSDKが不存在とは断定しない。
- 調査途中の[run 34454852968](https://github.com/cureflash/live2d-agent/actions/runs/34454852968)は候補検索の絞り込み不備があり、候補件数を無効とする。PowerShell 5.1ではLiteralPathとIncludeの組合せが効かない[公式仕様](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-childitem?view=powershell-5.1)を確認し、Filterと明示的な名前比較へ修正した。該当ログは拡張子別件数で、ファイル本文やフルパスは出力していない。
- 全ジョブでCeVIO接続なし。C++/CMakeの所在は確認済みだが、ビルド・描画・統合成功を示すものではない。
- 次の最小検証には公式Cubism SDK for Native一式の確保が必要。[公式ダウンロードページ](https://www.live2d.com/sdk/download/native/)にはダウンロード前の使用許諾確認がある。まだダウンロードや許諾同意、Editorの導入は実施していない。SDK入手後にバージョン・構成・ビルド条件を確認し、まず単体描画を試す。

### ダウンロード済みSDKとビルド準備の確認（2026-09-10）

- [ZIP検査](https://github.com/cureflash/live2d-agent/actions/runs/34456221156): Downloads内の `CubismSdkForNative-5-r.5.zip` を1件確認。27,566,034 bytes、1,354 entries、SHA256 `7FF3A4BBC19C0A8728965AA522AB77EB11B252916453E68A8A78D3B71188BB12`。これは実機ファイルの識別値であり、公式配布ハッシュとの照合ではない。
- ZIP内にCoreヘッダー、Windows x86/x86_64の141/142/143用ライブラリ、Framework、D3D11サンプルのCMake設定を確認。全エントリーのデータ完全性・描画互換性を保証する検査ではない。
- [ビルド条件照合](https://github.com/cureflash/live2d-agent/actions/runs/34456340201): 実機ツールセットは14.51.36231のみ、CMake 4.3.1-msvc1。SDKサンプルはMSVC_VERSION 1910以上1950未満を分類し、それ以外のMSVCを明示拒否する。D3D11サンプルはDirectXTKを別途必要とする。DirectXTKの取得・ビルドは未実施。
- [無改変SDK構成試験](https://github.com/cureflash/live2d-agent/actions/runs/34456505182): `1f7010088820187fd210ed6d52924681ac54f7b1`。ZIPをハッシュ再照合・展開先検査後、LocalAppData/live2d-agent/probes内の一意フォルダーへ展開。SDKソースは変更していない。CMakeはWindows SDK 10.0.26100.0、MSVC 19.51.36256.0を検出し、CMakeLists.txt:66で `Unsupported Visual C++ compiler used.`、終了コード1。アプリ本体のコンパイル・起動・描画は未実施。
- 現在の阻害要因は付属サンプルとインストール済みコンパイラーの不一致。次の候補はVS2022系v143 x64/x86ツールの追加と明示選択。追加は既存開発環境の変更に当たるため、ユーザー確認前には実施しない。SDKのバージョン判定を書き換えて成功扱いにはしない。
- [Microsoftのコンポーネント変更手順](https://learn.microsoft.com/en-us/visualstudio/install/modify-visual-studio)。導入時に実機Installerで対象コンポーネントと追加内容を確認する。
- SDK・展開ファイル・ビルド生成物のGit追加やArtifactsへのアップロードなし。CeVIOへの接続なし。ユーザーはSDK保存を報告したが、Editor導入・モデル表示成功を報告したものとは扱わない。

### v143追加の承認と中断状況（2026-09-10）

- ユーザーがv143追加を承認済み。再承認は不要。
- `.github/workflows/windows-v143-setup.yml` を追加し、まず対象コンポーネントのローカルカタログ登録・既存ツールセット・管理者権限を読む事前確認を実行。現段階のファイルにインストーラー起動処理はない。
- [事前確認run](https://github.com/cureflash/live2d-agent/actions/runs/34457369185)は08:52:57 UTCにランナーのshutdown signalを記録し、中断。インストール開始・完了を確認したものではない。停止理由は未確定。
- 読取り中に時間がかかっていたため、カタログJSON処理をNodeへ変更したが、元の中断原因がJSONパーサーだったとは断定しない。
- [再確認run](https://github.com/cureflash/live2d-agent/actions/runs/34457607405)は記録時点でqueued。専用ランナーの再接続が必要。事前確認は5分上限。同時実行時の旧ジョブ取消しは読取り専用段階の設定であり、インストール処理を追加する前に無効化する。
- CeVIO接続・インストーラー実行・強制再起動・既存アプリ終了は行っていない。
