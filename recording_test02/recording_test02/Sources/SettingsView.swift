import AVFoundation
import AudioToolbox
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
  }
}

// MARK: - 1. データ定義
// 警告音の選択肢を定義
struct SoundOption: Identifiable {
  let id: Int
  let name: String
  let fileName: String
}

let soundOptions: [SoundOption] = [
  SoundOption(id: 1052, name: "デフォルト", fileName: "alert_default"),
  SoundOption(id: 1005, name: "アラーム", fileName: "alert_alarm"),
  SoundOption(id: 1033, name: "チャイム", fileName: "alert_chime"),
  SoundOption(id: 1322, name: "警告", fileName: "alert_warning"),
]
// 端末の向きを定義
enum DeviceOrientationOption: String, CaseIterable, Identifiable {
  case portrait = "縦"
  case landscapeRight = "横"
  var id: String { self.rawValue }
}
// ペアマイクの選択肢を定義
enum MicSourceOption: String, CaseIterable, Identifiable {
  case back = "背面"
  case front = "前面"
  var id: String { self.rawValue }
}

// 入力/出力デバイスの選択肢を定義
enum InputDeviceOption: String, CaseIterable, Identifiable {
  case builtIn = "iPhone本体"
  case external = "接続デバイス"
  var id: String { self.rawValue }
}

enum OutputDeviceOption: String, CaseIterable, Identifiable {
  case speaker = "iPhone本体"
  case external = "接続デバイス"
  var id: String { self.rawValue }
}

//  モニタリング音源の選択肢を定義
enum MonitoringSoundSource: String, CaseIterable, Identifiable {
  case sweep = "スイープ信号 (20Hz-20kHz)"
  case pinkNoise = "ピンクノイズ"
  case whiteNoise = "ホワイトノイズ"
  case sineWave1k = "サイン波 (1kHz)"
  case cat = "猫の鳴き声"
  case beep = "ビープ音"

  var id: String { self.rawValue }

  // 実際のファイル名（プロジェクトにドラッグ&ドロップしたファイル名と合わせます）
  var fileName: String {
    switch self {
    case .sweep: return "sweep"
    case .pinkNoise: return "pink_noise"
    case .whiteNoise: return "white_noise"
    case .sineWave1k: return "sine_1k"
    case .cat: return "cat"
    case .beep: return "beep"
    }
  }
}

// MARK: - アイコン用コンポーネント
struct SettingsIconView: View {
  let systemName: String
  let color: Color

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 14, weight: .semibold))
      .foregroundColor(.white)
      .frame(width: 28, height: 28)
      .background(color)
      .cornerRadius(6)
  }
}

// MARK: - 2. SettingsView UI (メイン画面)
struct SettingsView: View {
  @AppStorage("isNoiseFilterEnabled") private var isNoiseFilterEnabled = false
  @AppStorage("warningSoundID") private var selectedSoundID: Int = 1052
  @AppStorage("deviceOrientation") private var selectedOrientation: DeviceOrientationOption =
    .landscapeRight
  @AppStorage("micSource") private var selectedMicSource: MicSourceOption = .back
  @AppStorage("isMonitoringEnabled") private var isMonitoringEnabled = false

  var body: some View {
    NavigationStack {
      Form {
        // MARK: - 一般設定セクション
        Section {
          Toggle(isOn: $isNoiseFilterEnabled) {
            HStack(spacing: 12) {
              SettingsIconView(systemName: "waveform.badge.minus", color: .green)
              Text("Noise Filter")
                .font(.system(size: 16))
            }
          }
          .tint(.green)

          NavigationLink(destination: AlertSoundSettingView()) {
            HStack(spacing: 12) {
              SettingsIconView(systemName: "bell.badge.fill", color: .red)
              Text("Alert Sound")
                .font(.system(size: 16))
              Spacer()
              Text(soundOptions.first { $0.id == selectedSoundID }?.name ?? "")
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
          }
        } header: {
          Text("General Settings")
        } footer: {
          Text("・録音時の環境ノイズを低減します(デコイ)\n・車両接近検知時の警告音を選択します")
            .font(.system(size: 12))
        }

        // MARK: - 録音設定セクション
        Section {
          // 端末の向き設定
          Picker(selection: $selectedOrientation) {
            ForEach(DeviceOrientationOption.allCases) { option in
              Text(option.rawValue).tag(option)
            }
          } label: {
            HStack(spacing: 12) {
              SettingsIconView(
                systemName: selectedOrientation == .portrait
                  ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate", color: .blue
              )
              Text("端末の向き")
            }
          }

          // ペアマイク設定（タップで別画面へ遷移）
          NavigationLink(destination: MicSourceSettingView()) {
            HStack(spacing: 12) {
              SettingsIconView(systemName: "mic.fill", color: .orange)
              Text("ペアマイク")
              Spacer()
              Text(selectedMicSource.rawValue)
                .foregroundColor(.secondary)
            }
          }

          // モニタリング機能のON/OFF
          NavigationLink(destination: MonitoringSettingView()) {
            HStack(spacing: 12) {
              SettingsIconView(systemName: "headphones", color: .pink)
              Text("モニタリング")
              Spacer()
              Text(isMonitoringEnabled ? "ON" : "OFF")
                .foregroundColor(.secondary)
            }
          }

        } header: {
          Text("Recording Settings")
        }

        // Aboutセクション
        Section {
          HStack {
            Text("Version")
              .font(.system(size: 16))
            Spacer()
            Text("2.2.0")
              .foregroundColor(.secondary)
          }
        } header: {
          Text("About")
        }
      }
      .navigationTitle("Settings")
    }
  }
}

// MARK: - 3. Component
// 警告音の選択画面
struct AlertSoundSettingView: View {
  @AppStorage("warningSoundID") private var selectedSoundID: Int = 1052
  
  // プレビュー再生用のオーディオプレイヤー
  @State private var audioPlayer: AVAudioPlayer?

  var body: some View {
    Form {
      Section {
        ForEach(soundOptions, id: \.id) { option in
          Button(action: {
            selectedSoundID = option.id
            playSoundPreview(fileName: option.fileName)
          }) {
            HStack {
              Text(option.name)
                .foregroundColor(.primary)
              Spacer()
              if selectedSoundID == option.id {
                Image(systemName: "checkmark")
                  .foregroundColor(.blue)
              }
            }
          }
        }
      }
    }
    .navigationTitle("Alert Sound")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)  // タブバーを隠す
    .onDisappear {
      // 画面を閉じた時に音が鳴っていれば強制停止
      audioPlayer?.stop()
    }
  }

  private func playSoundPreview(fileName: String) {
    audioPlayer?.stop()

    guard let url = Bundle.main.url(forResource: fileName, withExtension: "wav") else {
      print("エラー: \(fileName).wav が見つかりません。Xcodeプロジェクトにファイルを追加してください。")
      return
    }

    do {
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.numberOfLoops = 0
      audioPlayer?.play()
    } catch {
      print("再生エラー: \(error.localizedDescription)")
    }
  }
}

// ペアマイクの選択画面
struct MicSourceSettingView: View {
  @AppStorage("micSource") private var selectedMicSource: MicSourceOption = .back
  @AppStorage("deviceOrientation") private var selectedOrientation: DeviceOrientationOption =
    .landscapeRight

  var body: some View {
    Form {
      // 選択セクション
      Section {
        ForEach(MicSourceOption.allCases) { option in
          Button(action: {
            selectedMicSource = option
          }) {
            HStack {
              Text(option.rawValue)
                .foregroundColor(.primary)
              Spacer()
              if selectedMicSource == option {
                Image(systemName: "checkmark")
                  .foregroundColor(.blue)
              }
            }
          }
        }
      } header: {
        Text("ペアマイクの選択")
      }

      // プレビューセクション
      Section {
        VStack(spacing: 10) {
          ZStack {
            // マイク構成を中央に配置
            HStack(spacing: 15) {
              VStack(spacing: 6) {
                Image(systemName: "mic.fill").font(.title2).foregroundColor(.blue)
                Text("底面").font(.subheadline)
              }
              .frame(width: 70)

              Image(systemName: "plus").font(.body).foregroundColor(.secondary)

              VStack(spacing: 6) {
                Image(systemName: "mic.fill").font(.title2).foregroundColor(.green)
                Text(selectedMicSource == .back ? "背面" : "前面").font(.subheadline)
              }
              .frame(width: 70)
            }
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
        }
      } header: {
        Text("Mic Preview")
      }
    }
    .navigationTitle("ペアマイク")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)  // タブバーを隠す
  }
}

// モニタリング機能の設定画面
struct MonitoringSettingView: View {
  @AppStorage("isMonitoringEnabled") var isMonitoringEnabled: Bool = false
  @AppStorage("selectedInputDevice") var selectedInputDevice: InputDeviceOption = .builtIn
  @AppStorage("selectedOutputDevice") var selectedOutputDevice: OutputDeviceOption = .speaker

  // デバイスの接続状態（動的に更新）
  @State private var isExternalInputAvailable: Bool = false
  @State private var isExternalOutputAvailable: Bool = false

  // モニタリング音源の選択
  @AppStorage("selectedMonitoringSound") var selectedMonitoringSound: MonitoringSoundSource = .sweep

  var body: some View {
    Form {
      // 0. 注意喚起セクション
      Section {
        VStack(alignment: .leading, spacing: 16) {
          // アイコン部分
          Image(systemName: "headphones")
            .font(.system(size: 36, weight: .regular))
            .foregroundColor(.white)
            .frame(width: 64, height: 64)
            .background(Color.pink)
            .cornerRadius(16)

          // タイトル
          Text("モニタリング")
            .font(.title2)
            .bold()

          // 説明文
          Text("スピーカーからの音声をリアルタイムで録音します。\nハウリング防止のため、有線イヤホンやヘッドフォンの接続を強く推奨します。")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
      }

      // 1. メイントグル
      Section {
        Toggle(isOn: $isMonitoringEnabled) {
          HStack(spacing: 12) {
            SettingsIconView(systemName: "headphones", color: .pink)
            Text("モニタリング機能")
          }
        }
      }

      // 2. デバイス選択 (トグルON時のみ表示)
      if isMonitoringEnabled {
        // 録音デバイス（入力）
        Section {
          ForEach(InputDeviceOption.allCases) { option in
            let isAvailable = (option == .builtIn || isExternalInputAvailable)

            Button(action: {
              if isAvailable { selectedInputDevice = option }
            }) {
              HStack {
                Text(option.rawValue)
                  .foregroundColor(isAvailable ? .primary : .secondary)  // 未接続時はグレー
                Spacer()
                if selectedInputDevice == option {
                  Image(systemName: "checkmark")
                    .foregroundColor(isAvailable ? .blue : .secondary)
                }
              }
            }
            .disabled(!isAvailable)  // 未接続時はタップ不可
          }
        } header: {
          Text("録音デバイス")
        }

        // 再生デバイス（出力）
        Section {
          ForEach(OutputDeviceOption.allCases) { option in
            let isAvailable = (option == .speaker || isExternalOutputAvailable)

            Button(action: {
              if isAvailable { selectedOutputDevice = option }
            }) {
              HStack {
                Text(option.rawValue)
                  .foregroundColor(isAvailable ? .primary : .secondary)  // 未接続時はグレー
                Spacer()
                if selectedOutputDevice == option {
                  Image(systemName: "checkmark")
                    .foregroundColor(isAvailable ? .blue : .secondary)
                }
              }
            }
            .disabled(!isAvailable)  // 未接続時はタップ不可
          }
        } header: {
          Text("再生デバイス")
        }

        // 3. モニタリング音源の選択
        Section {
          NavigationLink(destination: MonitoringSoundSelectionView()) {
            HStack {
              Text(selectedMonitoringSound.rawValue)
                .foregroundColor(.secondary)
            }
          }
        } header: {
          Text("テスト音源")
        }
      }
    }
    .navigationTitle("モニタリング")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)  // タブバーを隠す
    .onAppear {
      checkDeviceAvailability()
    }
    // デバイスの抜き差し（ルート変更）を検知してUIを更新
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) {
      _ in
      checkDeviceAvailability()
    }
  }

  /// デバイスの接続状況を確認し、必要に応じて選択を安全な方に倒す
  private func checkDeviceAvailability() {
    let session = AVAudioSession.sharedInstance()

    // 入力: 内蔵マイク以外（有線マイク、Bluetooth等）があるか
    let availableInputs = session.availableInputs ?? []
    isExternalInputAvailable = availableInputs.contains { $0.portType != .builtInMic }

    // 出力: 内蔵スピーカー以外（ヘッドフォン、Bluetooth等）があるか
    let currentRoute = session.currentRoute
    isExternalOutputAvailable = currentRoute.outputs.contains { $0.portType != .builtInSpeaker }

    // 安全策：選択中のデバイスが抜かれたら「本体/スピーカー」に自動で戻す
    if !isExternalInputAvailable && selectedInputDevice == .external {
      selectedInputDevice = .builtIn
    }
    if !isExternalOutputAvailable && selectedOutputDevice == .external {
      selectedOutputDevice = .speaker
    }
  }
}

// MARK: - 音源選択およびプレビュー画面 (子画面)
struct MonitoringSoundSelectionView: View {
  @AppStorage("selectedMonitoringSound") var selectedMonitoringSound: MonitoringSoundSource = .sweep

  // プレビュー再生用のオーディオプレイヤー
  @State private var audioPlayer: AVAudioPlayer?

  var body: some View {
    Form {
      Section {
        ForEach(MonitoringSoundSource.allCases) { source in
          Button(action: {
            selectedMonitoringSound = source
            playSoundPreview(fileName: source.fileName)
          }) {
            HStack {
              Text(source.rawValue)
                .foregroundColor(.primary)
              Spacer()
              if selectedMonitoringSound == source {
                Image(systemName: "checkmark")
                  .foregroundColor(.blue)
              }
            }
          }
        }
      } footer: {
        Text("選択すると確認のために音が1回再生されます。")
      }
    }
    .navigationTitle("再生音源")
    .navigationBarTitleDisplayMode(.inline)
    .onDisappear {
      // 画面を閉じた時に音が鳴っていれば強制停止
      audioPlayer?.stop()
    }
  }

  /// 選択された音源を1回だけ再生する
  private func playSoundPreview(fileName: String) {
    // 前の音が鳴っていれば止める
    audioPlayer?.stop()

    // 今回は拡張子を "wav" と想定。mp3等を使う場合はここを変更してください。
    guard let url = Bundle.main.url(forResource: fileName, withExtension: "wav") else {
      print("エラー: \(fileName).wav が見つかりません。Xcodeプロジェクトにファイルを追加してください。")
      return
    }

    do {
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.numberOfLoops = 0  // ループなし（1回のみ）
      audioPlayer?.play()
    } catch {
      print("再生エラー: \(error.localizedDescription)")
    }
  }
}
