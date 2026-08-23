# Scene・保存・再生

## 保存領域

アプリはDocuments配下を使用します。

```text
Documents/
├── Default/
│   ├── Recording_20260821_01.wav
│   └── Detecting_20260821_01.csv
├── RoadTest/
└── Tunnel/
```

初回起動時に`Default`を作成します。旧バージョンでDocuments直下へ保存されていたWAVとCSVは、
同じ録音の関連ファイルを一組としてDefaultへ移行します。名前が衝突した場合は連番または
suffixを付け、既存ファイルを上書きしません。

選択中Sceneが存在しなくなった場合はDefaultへ戻します。

## Scene

Collections画面では次の操作を行えます。

- Scene作成
- Scene名変更
- Scene削除
- Scene内録音の表示
- Scene単位のZIP共有

Scene名は前後の空白を除去して保存します。空文字、`.`、`..`、`Default`、パス区切り文字、
改行、制御文字は使用できません。大文字・小文字やアクセントを無視して同名となるSceneも
作成できません。

Defaultは予約済みで、名称変更や削除の対象になりません。

## ファイル命名

```text
<Prefix>_yyyyMMdd_NN.<extension>
```

| 機能 | Prefix |
| --- | --- |
| 通常録音 | `Recording` |
| モニタリング | `Monitoring` |
| 検知 | `Detecting` |
| 音響特性測定 | `Analyze` |

連番は保存先、Prefix、日付ごとに既存WAVを調べ、最大値の次を使用します。
Analyzeが保存する周波数応答、メタデータ、IRの詳細は
[音響特性測定](analyze.md)を参照してください。

## Collections

- Scene名とDefault内録音を検索できます。
- Default内録音は日付順または名前順に並べ替えられます。
- Scene内録音は新しいファイル名順で表示されます。
- 左スワイプで削除、右スワイプでお気に入りを切り替えます。
- お気に入りは`<Scene名>/<ファイル名>`をキーとしてUserDefaultsへ保存します。

アイコンはファイル名から判定します。

- `Recording`：マイク
- `Monitoring`：ヘッドフォン
- その他：波形

## 録音削除

WAVを削除すると、存在する場合は次も同時に削除します。

```text
<basename>.wav
<basename>.csv
<basename>.json
Dev_<basename>.csv
<basename>_IR_CH1.wav
<basename>_IR_CH2.wav
```

現在の互換仕様では`Localization_<basename>.csv`は連動削除の対象外です。

## ZIP共有

Sceneのコンテキストメニューから共有形式を選択します。

| 選択 | 対象 |
| --- | --- |
| WAV | `.wav` |
| CSV | `Dev_`で始まらない`.csv` |
| Dev CSV | `Dev_`で始まる`.csv` |
| すべて | `.wav`、`.csv`、`.json` |

ZIPは外部ライブラリを使わず、無圧縮Stored形式で一時ディレクトリへ生成します。
アーカイブ名は`<Scene>_<Type>_yyyyMMdd.zip`です。

## Player

録音を選択するとPlayerへ遷移します。

- 再生／一時停止
- シーク
- 現在時間／総時間表示
- L/RレベルとdB表示
- WAV単体共有
- 録音削除
- ファイル名とメタデータ編集

縦画面では編集フォームをbottom sheetで表示し、横画面では画面右側へ常時表示します。

## Playerのメタデータ

次をUserDefaultsへ保存します。

- Experimenter
- Scene
- Weather
- Temperature
- Humidity
- Note

キーはWAVのファイル名を基準にします。異なるSceneに同名ファイルがある場合はメタデータが
衝突する可能性があります。これは既存データとの互換性を優先した現在の仕様です。

## ファイル名変更

Playerでbasenameを変更すると、次のファイルも存在する場合は同じbasenameへ変更します。

- WAV
- 通常CSV
- Dev CSV

現在の互換仕様ではLocalization CSVは連動変更の対象外です。変更前ファイル名のメタデータは
削除し、変更後ファイル名へ保存し直します。

## 速度表示

WAVと同じbasenameの通常CSVが存在する場合、Playerは`elapsed_time`と`speed_kmh`を読み込み、
現在の再生位置に最も近い行の速度を参照します。対応CSVがない録音では速度を表示しません。
