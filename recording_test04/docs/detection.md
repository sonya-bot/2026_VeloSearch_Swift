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

- モデル：`20260725-010849_hybrid_Best_model_epoch59`
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
- Audio I/O：現在の出力、入力、録音形式を表示し、タップすると詳細モーダルを表示

Developer設定でデバッグ表示をONにすると、角度、確率、推論更新間隔、特徴量生成と
推論のスキップ回数を表示します。

## 保存ファイル

Detectingsでは同じbasenameを持つ次のファイルを保存します。

```text
Detecting_yyyyMMdd_NN.wav
Detecting_yyyyMMdd_NN.csv
Dev_Detecting_yyyyMMdd_NN.csv
Localization_Detecting_yyyyMMdd_NN.csv
```

### 通常CSV

0.1秒間隔で速度、音量、状態、推論角度、推論確率、Ground Truth、端末向き、マイク、
基本的な処理状態を記録します。

### Dev CSV

通常CSVの情報に加え、更新時間、スキップ数、ビープ検出回数、定位状態、デバッグメッセージを
記録します。SettingsのDeveloper画面から一覧と内容を確認できます。

### Localization CSV

ビープイベント単位で、イベントID、モデル名、Ground Truth、推論角度、最大確率、
8方向すべての確率、ビープから推論完了までの時間、警告発生有無、推論成否を記録します。
