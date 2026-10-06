# 開発・テスト

## プロジェクト生成

`Project.swift`を正としてTuistでXcodeプロジェクトを生成します。

```bash
cd recording_test04
tuist install
./scripts/generate_project.sh
```

`tuist install`でFirebase Apple SDKを解決してから生成します。生成後は
`recording_test04.xcworkspace`を使用してください。SourcesやResourcesを追加した場合は再生成します。
生成スクリプトはFirebase Analytics由来の`StoreKit.framework`直接リンクを除外し、課金機能を
使用しない本アプリをPersonal Teamでも実機署名できる状態にします。

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

本プロジェクトはiOSアプリです。`-destination platform=macOS`ではなく、iOS Simulatorまたは
iOS実機を指定します。Simulator向けの確認では上記のように署名を無効化できます。実機へ
インストールする場合は、XcodeのSigning & CapabilitiesでDevelopment Teamを設定してください。

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
- WAV削除時の時系列／Localization／旧Dev CSV連動削除
- WAV改名時の関連CSV連動改名と衝突時の整合性
- 共有形式ごとの対象ファイル分類
- 診断CSVの取得と更新日時順ソート
- モデル名・選択の永続化、検証失敗時の復帰、計測中の変更禁止
- 5区間の時間、UI更新とCSV処理の順序、古い推論結果の除外
- CSVの引用符・改行、両CSVのプレビュー切り替え、旧CSV互換性
- 通常ファイル、ディレクトリ、存在しないパスの存在判定
- AppRootViewModelによるモニタリング設定反映
- Audio I/O設定の保存、旧出力設定の移行、出力ポート種別の識別
- ESS解析結果の有限性と1 kHz正規化

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
  --strict \
  --recursive \
  Project.swift \
  recording_test04/Sources \
  recording_test04/Tests
```

Swiftファイルは原則として1行120文字以内に保ちます。

## 変更時の確認事項

- Viewにファイル、データベース、Core ML、Core Locationへの直接アクセスを追加しないこと。
- 必須依存関係は`AppDependencies`またはFeatureのinitializerから注入すること。
- 画面状態はViewModel／Controller、外部アクセスはRepository／Service／Writerへ分離すること。
- 同じ目的のViewや操作ボタンはSharedまたはFeature内の共通部品を再利用すること。
- 保存ファイル名、UserDefaultsキー、CSV列を変更するときは既存データの移行を検討すること。
- 音声処理のサンプルレート、チャンネル数、特徴量順序をモデルの学習条件と一致させること。
- 新しい業務ロジックや不具合修正には、外部から観測できる振る舞いのテストを追加すること。
- 一時的な`print`を残さず、必要なログは`AppLogger`を使用すること。

## UI回帰確認

計測画面を変更した場合は、縦画面と横画面の両方で確認します。

- Settings以外の各タブで縦スクロールを発生させないこと。
- 横画面で全要素が表示範囲に収まり、左右カラムの位置関係が計測タブ間で揃うこと。
- Audio I/O表示の位置、外形、モーダルサイズが計測タブ間で揃うこと。
- Start／Stopなど同一機能のボタンが共通コンポーネントを使用していること。
- 実行中に保存先、方向タグ、反復回数を変更できないこと。

## 音源の追加

1. WAVを`recording_test04/Resources/Sounds`へ追加します。
2. `MonitoringSoundSource.fileName`を実際のbasenameと一致させます。
3. Tuistプロジェクトを再生成します。
4. Preview再生、Monitorings録音、自動停止を実機で確認します。

## Core MLモデルの追加・更新

開発時の配置先は、リポジトリルートから`recording_test04/Resources/models/`です。

```text
recording_test04/Resources/models/
├── CNN_CNN.mlpackage
├── CNN_RC.mlpackage
├── RC_CNN.mlpackage
└── RC_RC.mlpackage
```

同梱元は`/Users/Souma/Develop/Python/noise_reduction/comparison_models/`の各モデル配下です。
`.mlpackage`だけをコピーし、学習用`.pth`、training config、検証レポートはアプリへ同梱しません。
4モデルの出典・チェックサムは[同梱モデル](models.md)を参照してください。

1. `.mlpackage`を上記ディレクトリ直下へ配置します。ファイル名は一意にします。
2. 学習側の前処理が44.1 kHz、ステレオ、約2秒、5特徴量の順序と一致することを確認します。
3. 単一MultiArray入力の形状が`[1,5,64,173]`、出力は単一MultiArrayの8要素で、
   0°、45°、90°、135°、180°、225°、270°、315°の順序であることを確認します。
   入力はFloat16／Float32／Doubleへ対応し、必要な型変換はServiceが行います。
   サンプルレート・特徴量の意味・方向の順序はテンソル形状からは検証できないため、学習側で確認してください。
4. Tuistプロジェクトを再生成し、ビルドします。Xcodeが`.mlmodelc`へコンパイルしてBundleへ同梱します。
5. Settingsの「推論モデル」で選択し、実音声で角度、確率、時間、CSVを確認します。

モデル一覧はBundle内の`.mlmodelc`から取得するため、Swiftのモデル型名を編集する必要はありません。
表示・CSVのモデル名は末尾の拡張子を除いた名前です。`RC_CNN.v2.mlpackage`は`RC_CNN.v2`となります。
改名は別モデル名として扱い、保存済みの選択名が見つからなければCNN_CNNへ復帰して通知します。
現在はCNN_CNN／CNN_RC／RC_CNN／RC_RCの4モデルを同梱しています。初期選択はCNN_CNNです。
旧`20260725-010849_hybrid_Best_model_epoch59`とCNN_CNNはパッケージの全ファイルが一致するため、
旧選択名をCNN_CNNへ移行します。移行先の読み込みが成功するまで保存済み選択は変更しません。

依存ターゲットの最低対応OSは`Tuist/Package.swift`の`baseSettings`でiOS 18.0へ揃えています。
Xcode 27が拒否するFirebaseの間接依存のiOS 12設定も、プロジェクト生成時に置き換えます。
設定を変更した場合は`./scripts/generate_project.sh`で再生成し、生成済みプロジェクトは直接編集しません。

## アプリアイコンの更新

アプリアイコンは`recording_test04/Resources/Assets.xcassets/AppIcon.appiconset`で管理します。
1024×1024の元画像からiPhone／iPad用の各サイズを生成し、`Contents.json`の対応ファイル名を
維持してください。更新後はAsset Catalogの警告がないことと、実機・Simulatorのホーム画面で
小さいサイズでも主要図形が判別できることを確認します。

## Firebase Analytics

- Firebase依存関係はXcodeの生成済みプロジェクトではなく`Tuist/Package.swift`で管理します。
- AnalyticsはIDFAを使用しない`FirebaseAnalyticsCore`を選択します。
- Firebaseの初期化は`FirebaseAppDelegate`が担当します。
- `GoogleService-Info.plist`はローカル設定としてGit管理から除外します。新しい開発環境やCIでは、
  ビルド前に`recording_test04/Resources/Configuration`へ配置してください。
- Analyticsを利用するには、Firebase Console側でも対象プロジェクトのGoogle Analyticsを有効にします。

## 権限追加

マイクと使用中位置情報の説明は`Project.swift`のInfo.plist設定にあります。新しいOS権限を
使用する場合は、利用目的を明確にしたusage descriptionを同じ場所へ追加してください。
