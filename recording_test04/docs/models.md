# 同梱推論モデル

開発時の配置先は`recording_test04/Resources/models/`、実行時はアプリBundle内の`.mlmodelc`です。
元ファイル名から末尾の`.mlpackage`を除いた名前をSettings、計測画面、CSVへ共通で使用します。

同梱元：`/Users/Souma/Develop/Python/noise_reduction/comparison_models/`

| モデル名 | 同梱元の相対ディレクトリ | weight.binのSHA-256 |
| --- | --- | --- |
| `CNN_CNN` | `CNN_CNN/hybrid_20260725-010849` | `7299f600f3f6a19b6991f84f3eba131992a8b883e1b4775a3e151245d0dc04b7` |
| `CNN_RC` | `CNN_RC/phase4_m1000_20261001T153528+0900_7b476a79` | `7520498f00f529ef2c5f744fd225d5f7767ddfde2588666c7fc3f144398b37fe` |
| `RC_CNN` | `RC_CNN/RC_CNN_20261005T154313566636+0900_a70c8975` | `808133144048670b8d2f51bdbea1d7859586f3769b0dbeca767bb31d7c321af9` |
| `RC_RC` | `RC_RC/RC_RC_20261005T215658594362+0900_c4962af3` | `53684121cc2b38ff1b9bf2879deffb599dfdd05d97ee47e2bf53d3c99ce703a0` |

同梱時に4パッケージのmodel.mlmodel、weight.bin、Manifest.jsonを、各model_manifest.jsonの
artifact_checksumsと照合しました。CNN_CNNは旧同梱モデルの全ファイルとバイト単位で一致しています。
旧モデルは重複同梱せず、初期選択と旧選択名の移行先をCNN_CNNにします。

全モデルの契約は単一入力audioFeatures `[1,5,64,173]`、単一出力directionProbabilities `[1,8]`です。
特徴量はLogMel-L／LogMel-R／CosIPD／SinIPD／ILD、方向は0°から315°まで45°刻みです。
モデルの追加・更新時は、形状だけでなく学習時の前処理と出力順序の一致も確認してください。

アプリのテストでは4種類すべてを列挙し、実際の読み込み・推論・8方向出力と繰り返し入力の安定性を確認します。
ゼロ入力の互換性確認は実音声の精度検証とは別です。実機の処理時間・音源定位精度は実験で確認してください。
