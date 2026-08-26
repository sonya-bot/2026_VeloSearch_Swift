# アーキテクチャ

## 方針

本アプリはMVVMを基本とし、OS機能と永続化処理をRepository／Serviceへ分離しています。
Viewは表示とユーザー操作の宣言を担当し、外部リソースへのアクセスは注入された依存関係を
通して行います。

```text
App / ContentView
        │
        ▼
AppRootView ─── AppRootViewModel
        │
        ├── Detection Feature
        ├── Recording / Monitoring Feature
        ├── Analyze Feature
        ├── Collections / Player Feature
        └── Settings Feature
                 │
                 ▼
      Repository / Service / Apple Framework
```

## App層

### ContentView

`ContentView`はプレビューと既存呼び出し元のための軽量な公開エントリーポイントです。
実際のタブ構成は`AppRootView`へ委譲します。

### FirebaseAppDelegate

SwiftUIのアプリライフサイクルへ`UIApplicationDelegateAdaptor`で接続し、起動時にFirebaseを
初期化します。Analyticsには広告識別子を含まない`FirebaseAnalyticsCore`を使用します。

### AppRootView

次の5タブを構成し、各Featureへ依存関係を渡します。

1. Detectings
2. RecordingsまたはMonitorings
3. Analyze
4. Collections
5. Settings

### AppRootViewModel

- 選択中のタブを保持します。
- `isMonitoringEnabled`の変更を監視します。
- UI状態の更新をMainActor上で行います。

### AppDependencies

アプリで共有する依存関係をまとめます。

- `RecordingFileStoring`
- `UserDefaults`
- `NotificationCenter`
- `AudioIOController`
- `LocationService`
- `AudioPreviewController`
- `AnalyzeResultWriting`

本番では`AppDependencies.live`を使用し、テストでは専用の依存関係へ差し替えられます。

## Feature層

| Feature | 主な責務 |
| --- | --- |
| Detection | 検知セッションの状態、レーダー、方向確率、共通テスト音源の再生を管理します。 |
| Recording | 通常録音、レベル表示、保存先選択を管理します。 |
| Monitoring | テスト音源を使った録音と自動停止を管理します。 |
| Analyze | ESS測定、IR・周波数応答解析、反復実行を管理します。 |
| Collections | Sceneと録音一覧、検索、お気に入り、共有を管理します。 |
| Player | WAV再生、シーク、編集、対応CSVへの導線、単体共有を管理します。 |
| Settings | 永続設定とデバッグCSVへの導線を管理します。 |

`CollectionsViewModel`などのViewModelは画面状態と操作を保持します。録音、再生、検知のように
長時間継続する処理はObservableなControllerが状態を公開し、Viewはその状態を表示します。
Monitoringsの反復回数、カウントダウン、ターム遷移は`MonitoringSequenceController`が管理します。

巨大なFeatureを単一ファイルへ集約せず、次の単位へ分割します。

- View：レイアウトと操作の宣言
- ViewModel／Controller：画面状態、計測シーケンス、ユーザー操作の調停
- Service：録音、再生、解析、Core ML、位置情報などのOS・計算処理
- Repository／Writer：ファイル名、Scene、CSV、JSON、WAV、ZIPの永続化

DetectionのControllerは音声処理、方向推定、ログをextensionファイルへ分割しています。
Analyzeの計測、解析、結果出力、Playerの再生、付帯情報、CollectionsのScene内録音管理も
それぞれ独立した型で扱います。

## Infrastructure層

### Audio

- `AudioFeatureExtractor`：ステレオ音声からCore ML入力特徴量を生成します。
- `BeepDetector`：Goertzel法を用いてビープ帯域を検出します。
- `DirectionModelService`：Core MLモデルを読み込み、8方向の確率を返します。
- `AudioPreviewController`：設定画面で選択した警告音とテスト音源を共通の経路で試聴します。
- `ESSAnalyzer`：録音信号とESSからIR、周波数応答を算出します。

### Location

`LocationService`がCore Locationを使用して速度を取得します。負の速度は0として扱います。

### Storage

`RecordingFileStoring`がFeature層から見えるインターフェースです。
`RecordingFileStore`がDocuments、Scene、録音、関連ファイルの改名・削除、CSV読み込みを管理し、
`StoredZIPWriter`が共有用ZIPを生成します。Analyze固有のCSV、JSON、IR出力は
`AnalyzeResultWriting`を介して`AnalyzeResultWriter`が担当します。

## Shared層

- `AppLogger`：OSLogのカテゴリを一元化します。
- `CSVPreviewView`：Dev CSVと録音に対応する通常CSVを表形式で表示します。
- `CSVPreviewViewModel`：RepositoryからCSVを読み込み、表示用の行へ変換します。
- `MeasurementLandscapeLayout`：各計測タブの横画面カラム位置を統一します。
- `MeasurementControlButton`：計測開始・停止ボタンの外形と状態表現を統一します。

Analyzeの詳細グラフは、通常画面の縮小グラフとは分離したViewで目盛り、軸ラベル、選択カーソルを
描画します。Playerの通常CSV導線はFeature内の共通部品を縦横レイアウトと編集画面から再利用し、
ファイルの存在確認と読み込みは`RecordingFileStoring`を通して行います。

## 依存方向

- ViewからFileManager、Core MLモデル、Core Locationを直接操作しません。
- Featureは`RecordingFileStoring`や専用Writerを通して保存処理を行います。
- 具体的な依存関係はアプリルートで生成し、各画面へ注入します。
- テストでは一時Documentsと専用UserDefaults suiteを使用します。

## 状態の永続化

設定は既存バージョンとの互換性を保つためUserDefaultsへ保存します。録音本体とCSVは
Documentsへ保存し、UIの一時状態とは分離します。
