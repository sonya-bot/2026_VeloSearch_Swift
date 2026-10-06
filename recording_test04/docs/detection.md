# 検知・音源定位

## 概要

Detectings画面は、ステレオ音声と移動速度を記録しながらビープ音を監視します。
ビープを検出すると周辺音声から特徴量を生成し、Core MLモデルで音源方向を推定します。

## 操作

1. SettingsでAudio I/O、共通テスト音源、警告音を選択します。
2. 保存先と方向タグを選択します。
3. Detectingsタブで`Start`を押します。
4. 任意のタイミングで`Test`を押すと共通テスト音源を再生し、再度押すと停止します。
5. `Stop`を押すとWAVとCSVを保存します。

方向タグは0°から315°まで45°刻みで選択でき、実行開始時に固定されます。

## 処理フロー

```text
Standby
  │ Start
  ▼
Safe / ビープ待機
  │ ビープ検出
  ▼
定位音声収集
  │ 2秒相当の音声が揃う
  ▼
特徴量生成
  ▼
Core ML推論
  ├── 最大確率 40%以上 ── Detect
  └── 最大確率 40%未満 ── Uncertain
                         │ 3秒後
                         ▼
                        Safe
```

## 音声入力

- 目標サンプルレート：44,100 Hz
- チャンネル：ステレオ2チャンネル
- 内部形式：Float32、non-interleaved
- Audio Engine tap buffer：4,096 frames
- 保存形式：目標形式を使ったWAV

入力形式が異なる場合は`AVAudioConverter`で目標形式へ変換します。

## ビープ検出

ビープ検出にはGoertzel法を使用します。

- 対象周波数：420、430、440、450、460 Hz
- 比較周波数：250、300、600、700、900、1,200 Hz
- 最低音量：-60 dB
- 最低帯域比：5.0
- 必要な連続検出回数：3回
- 再検出防止時間：2.2秒

同梱する`beep.wav`は約2秒の実験用ビープです。

## 特徴量生成

- 推論対象音声：88,200 samples、約2秒
- ビープ前のpre-roll：22,050 samples、約0.5秒
- FFTサイズ：1,024
- hop length：512
- Mel bin：64
- frame数：173
- 更新step：11,025 samples

学習時の前処理に合わせ、Hann窓、center相当のreflect padding、Melフィルターを適用します。
Core MLへ渡すテンソル形状は`[1, 5, 64, 173]`です。

5チャンネルは次の特徴量で構成されます。

1. 左チャンネルLog-Mel
2. 右チャンネルLog-Mel
3. cos IPD
4. sin IPD
5. ILD

## Core ML推論

- 初期モデル：`CNN_CNN`
- 同梱モデル：`CNN_CNN`、`CNN_RC`、`RC_CNN`、`RC_RC`
- Settingsの「推論モデル」で同梱モデルを選択します。モデル名は元のファイル名から末尾の
  `.mlpackage`だけを除いた名前です。`RC_CNN.mlpackage`は`RC_CNN`、`RC_CNN.v2.mlpackage`は
  `RC_CNN.v2`として表示・記録します。
- 選択は再起動後も維持され、計測中のモデル変更はできません。モデルの読み込みと入出力検証が
  成功してから選択を確定します。失敗時は直前のモデルを維持し、起動時はCNN_CNNへの復帰を通知します。
  利用可能なモデルがない場合はStartを無効化します。
- 対応入力は`[1, 5, 64, 173]`の単一MultiArray、対応出力は8要素の単一MultiArrayです。
  特徴量の意味と方向の順序は全モデルで共通にする必要があります。
- 出力クラス数：8
- 角度：0°、45°、90°、135°、180°、225°、270°、315°
- Detect判定閾値：最大確率0.40

最大確率のクラスを角度へ変換します。Detectになった連続期間では警告音を最初の1回だけ
鳴らします。結果は3秒間表示され、その後Safeへ戻ります。

## 表示

- Standby：停止中
- Safe：録音中で検知結果なし
- Uncertain：推論したが閾値未満
- Detect：閾値以上の方向を検知
- レーダー：Detect時に推論方向の45°扇形を表示
- Status：縦横画面ともレーダー領域の上部に表示
- 横画面のDetection probability見出し右側：停止中は選択モデル名、計測中は使用モデル名を表示。
  長いモデル名は末尾を省略し、時間・音量の領域を確保します。利用不可時は「モデル未選択」を表示。
- Audio I/O：現在の出力、入力、録音形式を表示し、タップすると詳細モーダルを表示

Developer設定でデバッグ表示をONにすると、角度、確率、推論更新間隔、特徴量生成と
推論のスキップ回数を表示します。

## 保存ファイル

Detectingsでは同じbasenameを持つ次のファイルを保存します。

```text
Detecting_yyyyMMdd_NN.wav
Detecting_yyyyMMdd_NN.csv
Localization_Detecting_yyyyMMdd_NN.csv
```

### 時系列CSV

`<basename>.csv`へ0.1秒間隔で速度、音量、検知状態、角度・確率、正解方向、端末向き、マイク、
更新間隔、スキップ数、ビープ検出数、定位状態、処理成否、デバッグメッセージを記録します。
従来の通常CSVとDev CSVを統合したもので、新しい`Dev_`ファイルは作成しません。
先頭2列の`elapsed_time`（秒）と`speed_kmh`を維持し、Playerの速度表示にも使用します。

### 推論イベントCSV

`Localization_<basename>.csv`へ推論イベントごとに1行を保存します。
モデル名、正解方向、推論角度、最大確率、判定、8方向の全確率、警告要求の有無と、
以下の性能・実験条件を記録します。CSV形式バージョンは`2`です。

| 時間列 | 計測区間 |
| --- | --- |
| `audio_collection_ms` | ビープ検出から音声収集完了 |
| `feature_extraction_ms` | 特徴量生成開始から完了 |
| `inference_ms` | Core MLのprediction呼び出し開始から終了（入力変換・出力解釈は含まない） |
| `ui_update_ms` | prediction終了からMainActorで結果のUI状態を更新するまで |
| `total_ms` | ビープ検出からUI状態更新まで |

時間は単調時計で計測し、ミリ秒・小数点以下3桁で保存します。
`beep_detected_time`、`audio_ready_time`、`feature_started_time`、`feature_completed_time`、
`prediction_started_time`、`inference_completed_time`、`ui_updated_time`は計測開始からの秒数です。
既存の`prediction_completed_time`もCore ML呼び出し終了時刻、`beep_to_prediction_ms`は従来同様に
UI反映までの全体時間を記録します。`elapsed_time`はUI更新時、または中止時の経過秒数です。
実際の描画完了・音の鳴り始めは計測していません。

`device_model`、`os_version`、`app_version`、`build_number`、`detection_threshold`を各イベントへ記録します。
モデル実行環境はCore MLのcomputeUnits `.all`です。使用される実際のCPU/GPU/ANEはOSが選択します。
`outcome`は`success`、`failure`、`cancelled`で、`failure_kind`に分類を記録します。
未計測時間と未取得の確率は空欄です。計測停止時の未完了イベントも中止行として保存し、
停止・再開始後に古いイベントを新しいUI・CSVへ反映しません。

推論後は意図的な待機を入れずMainActorでUI状態を更新し、その後CSV行を整形します。
結果を3秒間保持する仕様は維持します。CSVのファイル保存はStop時にRepositoryを介して行います。

通常CSV・旧Dev CSV・イベントCSVは、同じCSVプレビューで時系列／推論イベントを切り替えて確認できます。
