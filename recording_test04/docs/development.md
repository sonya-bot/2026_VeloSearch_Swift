# 開発・テスト

## プロジェクト生成

`Project.swift`を正としてTuistでXcodeプロジェクトを生成します。

```bash
cd recording_test04
tuist generate --no-open
```

生成後は`recording_test04.xcworkspace`を使用してください。SourcesやResourcesを追加した場合は
再生成します。

## ビルド

```bash
xcodebuild \
  -workspace recording_test04.xcworkspace \
  -scheme recording_test04 \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

マイク、ステレオ入力、Audio Session route、位置情報、警告音は実機でも確認してください。

## テスト

```bash
xcodebuild \
  -workspace recording_test04.xcworkspace \
  -scheme recording_test04 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

現在のテストでは主に次を検証します。

- Defaultフォルダの作成
- 日付と連番による録音URL生成
- 選択中Sceneの名称変更
- WAV削除時の通常CSV／Dev CSV連動削除
- 共有形式ごとの対象ファイル分類
- AppRootViewModelによるモニタリング設定反映

ストレージテストは一時ディレクトリと専用UserDefaults suiteを使用し、実際のDocumentsや
ユーザー設定を変更しません。

## FormatとLint

```bash
xcrun swift-format format \
  --in-place \
  --recursive \
  Project.swift \
  recording_test04/Sources \
  recording_test04/Tests

xcrun swift-format lint \
  --recursive \
  Project.swift \
  recording_test04/Sources \
  recording_test04/Tests
```

Swiftファイルは原則として1行120文字以内に保ちます。

## 変更時の確認事項

- Viewにファイル、データベース、Core ML、Core Locationへの直接アクセスを追加しないこと。
- 必須依存関係は`AppDependencies`またはFeatureのinitializerから注入すること。
- 保存ファイル名、UserDefaultsキー、CSV列を変更するときは既存データの移行を検討すること。
- 音声処理のサンプルレート、チャンネル数、特徴量順序をモデルの学習条件と一致させること。
- 新しい業務ロジックや不具合修正には、外部から観測できる振る舞いのテストを追加すること。
- 一時的な`print`を残さず、必要なログは`AppLogger`を使用すること。

## 音源の追加

1. WAVを`recording_test04/Resources/Sounds`へ追加します。
2. `MonitoringSoundSource.fileName`を実際のbasenameと一致させます。
3. Tuistプロジェクトを再生成します。
4. Preview再生、Monitorings録音、自動停止を実機で確認します。

## Core MLモデルの更新

1. `.mlpackage`を`recording_test04/Resources/models`へ配置します。
2. `DirectionModelService`のモデル型と`modelName`を更新します。
3. 入力テンソル形状が`AudioFeatureExtractor`の出力と一致することを確認します。
4. 出力が8方向の確率であること、値が有限かつ0以上であることを確認します。
5. 実音声で角度、閾値、CSV出力、処理時間を検証します。

## 権限追加

マイクと使用中位置情報の説明は`Project.swift`のInfo.plist設定にあります。新しいOS権限を
使用する場合は、利用目的を明確にしたusage descriptionを同じ場所へ追加してください。
