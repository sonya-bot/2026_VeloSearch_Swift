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

入出力デバイスと録音形式は全タブ共通です。入力は接続中の具体的な機器、出力はiOSのシステム経路
選択画面からiPhone、USB、Bluetoothなどを選択します。録音形式はAutomatic／Mono／Stereoから
選択します。現在成立している経路は各タブ共通の表示専用モーダルで
確認できます。入力変更時に選択内容をオーディオセッションへ適用し、具体的なポートUID、出力種別、
チャンネル数、マイク構成を検証します。BluetoothやUSBの出力はアプリから強制せず、システム経路
選択後の実経路を保存します。計測中は設定を変更できません。

iPhone内蔵マイクでは、複数マイクによるStereo構成を維持するため`.default`セッションモードを
使用します。USBなどの外部入力では、信号処理を抑える`.measurement`モードを使用します。

計測タブ側のAudio I/O表示は設定操作を持ちません。出力、入力、Formatをアイコンと接続方式で
表示し、iPhone入力では端末向きをアイコンで区別します。Stereo時だけチャンネル詳細を表示し、
iPhone入力では`Back + Bottom`または`Front + Bottom`、外部入力では`L / R`とします。
適用中は`確認中`、経路が成立していない場合は`利用不可`として、未確認の状態をMonoとは表示しません。
計測開始時は成立済みの経路を再設定せず検証し、実行中に経路が変わった場合は計測を停止します。

端末の向きとマイク構成もこの画面へ統合します。iPhone入力時のみ端末の向きを表示し、
iPhoneかつStereo指定時のみマイク構成への導線を表示します。Settings直下には重複項目を
設けません。

#### 端末の向き

- キー：`deviceOrientation`
- 初期値：`Landscape`
- 選択肢：`Portrait`、`Landscape`

AVAudioSessionの入力orientationへ反映します。

#### マイク構成

- キー：`micSource`
- 初期値：`Back`
- 選択肢：`Back`、`Front`

底面マイクと、選択した前面または背面マイクの組み合わせを表示します。外部入力ではこの設定を
使用せず、StereoチャンネルをL/Rとして扱います。

### モニタリング

- キー：`isMonitoringEnabled`
- 初期値：OFF

ONにするとルート画面の2番目のタブがRecordingsからMonitoringsへ切り替わります。

#### 録音デバイス

- キー：`selectedInputDevice`
- 初期値：`iPhone`
- 選択肢：現在接続中のiPhone、USB、Bluetooth HFP、有線またはその他の入力機器
- 補助キー：`selectedInputDeviceUID`

Detectingsは機能要件として、共通設定で選択した入力に2チャンネルを要求します。

#### 再生デバイス

- キー：`selectedOutputDevice`
- 初期値：`iPhone`
- 選択肢：システム経路選択画面に表示されるiPhone、USB、Bluetoothなど
- 補助キー：`selectedOutputDeviceUID`

選択した具体的な出力経路が成立しない場合は利用不可として、再選択を求めます。

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
| `selectedInputDeviceUID` | 選択した入力ポートUID |
| `selectedOutputDevice` | 共通出力 |
| `selectedOutputDeviceUID` | 選択した出力ポートUID |
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
