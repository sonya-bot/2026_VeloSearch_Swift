# 設定

設定はUserDefaultsへ保存され、アプリの再起動後も維持されます。

## General Settings

### Noise Filter

- キー：`isNoiseFilterEnabled`
- 初期値：OFF

現在は設定UIと永続化のみで、録音や特徴量生成には反映されません。

### Alert Sound

- キー：`warningSoundID`
- 初期値：1052

| 表示名 | System Sound ID |
| --- | ---: |
| デフォルト | 1052 |
| アラーム | 1005 |
| チャイム | 1033 |
| 警告 | 1322 |

Detect判定時に選択されたSystem Sound IDを使用します。連続したDetect期間では最初の1回だけ
再生します。

## Recording Settings

### Audio Input / Output

入出力デバイスと録音形式は全タブ共通です。入力・出力はiPhoneまたは接続デバイス、録音形式は
Automatic／Mono／Stereoから選択します。現在成立している経路は各タブ共通の表示専用モーダルで
確認できます。実行できない組み合わせでは設定を自動変更せず、開始操作を無効にします。

### 端末の向き

- キー：`deviceOrientation`
- 初期値：横
- 選択肢：縦、横

AVAudioSessionの入力orientationへ反映します。

### ペアマイク

- キー：`micSource`
- 初期値：背面
- 選択肢：背面、前面

底面マイクと、選択した前面または背面マイクの組み合わせを画面に表示します。

### モニタリング

- キー：`isMonitoringEnabled`
- 初期値：OFF

ONにするとルート画面の2番目のタブがRecordingsからMonitoringsへ切り替わります。

#### 録音デバイス

- キー：`selectedInputDevice`
- 初期値：iPhone本体
- 選択肢：iPhone本体、接続デバイス

Detectingsは機能要件としてiPhoneのステレオ入力を使用し、その他の計測機能は共通設定を使用します。

#### 再生デバイス

- キー：`selectedOutputDevice`
- 初期値：iPhone本体
- 選択肢：iPhone本体、接続デバイス

接続経路が成立しない場合も設定値を変更せず、計測開始前にエラーとして表示します。

#### テスト音源

- キー：`selectedMonitoringSound`
- 初期値：スイープ信号5秒

Settingsの共通項目として選択し、Detectingsの`Test`とMonitoringsで同じ音源を使用します。
音源を選ぶと確認のため1回再生します。

## Developer

### デバッグ表示

- キー：`showDebugOverlay`
- 初期値：OFF

ONにするとDetectings画面へ次を表示します。

- AI推論角度と最大確率
- 推論更新間隔
- 特徴量生成スキップ数
- AI推論スキップ数

### Debug CSV

DefaultとすべてのSceneから`Dev_`で始まるCSVを収集し、更新日時の新しい順に表示します。
選択したCSVは横・縦方向にスクロールできる表として表示します。

## About

設定画面上の表示バージョンは`2.2.0`です。これは既存画面との互換表示であり、
ビルド番号やInfo.plistのmarketing versionを自動参照するものではありません。

## UserDefaultsキー一覧

| キー | 用途 |
| --- | --- |
| `isNoiseFilterEnabled` | Noise Filter |
| `warningSoundID` | 警告音 |
| `deviceOrientation` | 端末向き |
| `micSource` | 前面／背面マイク |
| `isMonitoringEnabled` | モニタリング有効化 |
| `selectedInputDevice` | 共通入力 |
| `selectedOutputDevice` | 共通出力 |
| `recordingChannelMode` | Automatic／Mono／Stereo |
| `measurementDirectionTag` | Detecting／Monitoring／Analyze共通方向タグ |
| `monitoringRepeatCount` | Monitoring実行回数 |
| `analyzeRepeatCount` | Analyze実行回数 |
| `selectedMonitoringSound` | テスト音源 |
| `showDebugOverlay` | Detectingsデバッグ表示 |
| `selectedSceneFolderName` | 現在の保存先Scene |
| `favoriteAudios` | お気に入り録音 |

Playerのメタデータはファイル名へ`_note`、`_experimenter`、`_weather`、`_temperature`、
`_humidity`、`_scene`を付加したキーで保存します。
