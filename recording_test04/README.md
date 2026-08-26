# recording_test04

`recording_test04`は、モノラル／ステレオ録音、テスト音源を利用したモニタリング録音、
Core MLによる8方向の音源定位、ESSによる音響特性測定、計測データ管理を行うiOSアプリです。

`recording_test03`の画面・保存形式・設定値との互換性を維持しながら、MVVMを基本とする
責務分離、依存性注入、Repository／Serviceによる外部機能の抽象化を行っています。

## 主な機能

| 機能        | 概要                                                                              |
| ----------- | --------------------------------------------------------------------------------- |
| Detectings  | 音声を録音し、ビープ検出後にCore MLで音源方向を8方向へ分類します。                |
| Recordings  | 44.1 kHz、16-bit PCM、モノラル／ステレオWAVを録音します。                         |
| Monitorings | 選択したテスト音源を再生しながらモノラル／ステレオ録音します。                    |
| Analyze     | 同梱版と同条件の20 Hz〜20 kHz・30秒ESSを生成し、IRと周波数応答を解析・拡大表示します。 |
| Collections | DefaultとSceneごとに録音を一覧表示し、検索、削除、お気に入り、ZIP共有を行います。 |
| Player      | WAVの再生、シーク、レベル表示、名称変更、メタデータ編集、対応CSVの確認、共有を行います。 |
| Settings    | 共通の入出力・録音形式、端末向き、使用マイク、警告音などを設定します。            |

画面は5つのタブで構成されます。モニタリング設定がOFFの場合は2番目のタブが
Recordings、ONの場合はMonitoringsになり、Analyzeは独立したタブです。

## 必要な権限

- マイク：録音と音源定位に使用します。
- 使用中の位置情報：Detectingsの計測CSVへ速度を記録するために使用します。

実機で初めて機能を使用するときは、表示される権限ダイアログで許可してください。

## 開発環境

- macOS
- Xcode
- Tuist 4系
- iOS 18.0以降
- iOS実機（マイク、ステレオ入力、位置情報を含む動作確認に必要）

SwiftUI、AVFoundation、Core ML、Core Location、AccelerateなどのApple Frameworkに加え、
Firebase Apple SDKの`FirebaseCore`とIDFAを使用しない`FirebaseAnalyticsCore`を使用します。

## セットアップ

```bash
cd recording_test04
tuist install
./scripts/generate_project.sh
open recording_test04.xcworkspace
```

生成スクリプトは、Firebase Analyticsが追加する`StoreKit.framework`のアプリターゲットへの
直接リンクを除外します。これにより、課金機能を使用しない本アプリをPersonal Teamで実機署名できます。

Xcodeで`recording_test04` schemeと実行先を選択し、ビルドまたは実行します。

コマンドラインでSimulator向けにビルドする場合は、次を使用します。

```bash
xcodebuild \
  -workspace recording_test04.xcworkspace \
  -scheme recording_test04 \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## テストとフォーマット

```bash
xcodebuild \
  -workspace recording_test04.xcworkspace \
  -scheme recording_test04 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO \
  test

xcrun swift-format lint \
  --recursive \
  Project.swift \
  recording_test04/Sources \
  recording_test04/Tests
```

Simulator名は、ローカル環境にインストールされているデバイスへ置き換えてください。

## プロジェクト構成

```text
recording_test04/
├── Project.swift
├── README.md
├── docs/
├── Tuist/
└── recording_test04/
    ├── Resources/
    ├── Sources/
    │   ├── App/
    │   ├── Features/
    │   ├── Infrastructure/
    │   └── Shared/
    └── Tests/
```

- `App`：アプリのエントリーポイント、ルート画面、依存関係を管理します。
- `Features`：画面と画面単位の状態・操作を管理します。
- `Infrastructure`：音声、Core ML、位置情報、ファイル保存を扱います。
- `Shared`：複数機能から利用する表示部品とログを管理します。

## 詳細ドキュメント

- [アーキテクチャ](docs/architecture.md)
- [検知・音源定位](docs/detection.md)
- [録音・モニタリング](docs/recording-and-monitoring.md)
- [音響特性測定](docs/analyze.md)
- [Scene・保存・再生](docs/storage-and-playback.md)
- [設定](docs/settings.md)
- [開発・テスト](docs/development.md)

## 保存データ

録音、CSV、JSON、IRはアプリのDocuments配下へ保存されます。全計測タブで保存先を選択でき、
初回起動時に作成する`Default`と、ユーザーが作成したSceneを同じ階層で管理します。

```text
Documents/
├── Default/
└── <Scene名>/
```

ファイル名、CSV列、削除・共有範囲については
[Scene・保存・再生](docs/storage-and-playback.md)を参照してください。

## 現在の仕様上の注意

- Noise Filterは設定UIのみで、音声処理にはまだ反映されません。
- テスト音源の選択画面には、現在リソースが同梱されている音源だけを表示します。
- Audio I/Oモーダルは全計測タブ共通の表示専用UIです。Settingsでの変更時に実機へ適用・検証し、
  入力は具体的なポート、出力はシステム経路選択後の種別とUIDを保存して全タブへ反映します。
- マイク構成やステレオ入力の可否は端末によって異なるため、主要機能は実機で確認してください。

これらは`recording_test03`との挙動互換性を維持するため、現在は変更していません。
