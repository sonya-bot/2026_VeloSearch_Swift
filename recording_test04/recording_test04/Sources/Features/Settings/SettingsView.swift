import AVFoundation
import AudioToolbox
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView(
      recordingFileStore: RecordingFileStore.shared,
      audioIOController: AudioIOController()
    )
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
//  モニタリング音源の選択肢を定義
enum MonitoringSoundSource: String, CaseIterable, Identifiable {
  case sweep5Seconds = "スイープ信号 (5秒)"
  case sweep10Seconds = "スイープ信号 (10秒)"
  case sweep30Seconds = "スイープ信号 (30秒)"
  case pinkNoise = "ピンクノイズ"
  case whiteNoise = "ホワイトノイズ"
  case sineWave1k = "サイン波 (1kHz)"
  case cat = "猫の鳴き声"
  case beep = "ビープ音"

  var id: String { self.rawValue }

  static var availableCases: [Self] {
    allCases.filter(\.isBundled)
  }

  var isBundled: Bool {
    switch self {
    case .sweep5Seconds, .sweep10Seconds, .sweep30Seconds, .cat, .beep:
      return true
    case .pinkNoise, .whiteNoise, .sineWave1k:
      return false
    }
  }

  // 実際のファイル名（プロジェクトにドラッグ&ドロップしたファイル名と合わせます）
  var fileName: String {
    switch self {
    case .sweep5Seconds: return "sweep_5s"
    case .sweep10Seconds: return "sweep_10s"
    case .sweep30Seconds: return "sweep_30s"
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
  private let recordingFileStore: RecordingFileStoring
  @ObservedObject private var audioIOController: AudioIOController
  @AppStorage("isNoiseFilterEnabled") private var isNoiseFilterEnabled = false
  @AppStorage("warningSoundID") private var selectedSoundID: Int = 1052
  @AppStorage("isMonitoringEnabled") private var isMonitoringEnabled = false
  @AppStorage("selectedMonitoringSound") private var selectedTestSound = MonitoringSoundSource
    .sweep5Seconds
  @AppStorage("showDebugOverlay") private var showDebugOverlay = false

  init(
    recordingFileStore: RecordingFileStoring,
    audioIOController: AudioIOController
  ) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
  }

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
          Text(
            "・録音時の環境ノイズを低減します(デコイ)\n"
              + "・車両接近検知時の警告音を選択します"
          )
          .font(.system(size: 12))
        }

        // MARK: - 録音設定セクション
        Section {
          NavigationLink(
            destination: AudioIOSettingsView(audioIOController: audioIOController)
          ) {
            HStack(spacing: 12) {
              SettingsIconView(systemName: "waveform.circle.fill", color: .blue)
              Text("Audio Input / Output")
              Spacer()
              Text(audioIOController.activeConfiguration.channelLabel)
                .foregroundStyle(.secondary)
            }
          }

          NavigationLink(destination: TestSoundSelectionView()) {
            HStack(spacing: 12) {
              SettingsIconView(systemName: "speaker.wave.2.fill", color: .orange)
              Text("テスト音源")
              Spacer()
              Text(selectedTestSound.rawValue)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

        // MARK: - デベロッパセクション
        Section {
          NavigationLink(
            destination: DeveloperSettingsView(recordingFileStore: recordingFileStore)
          ) {
            HStack(spacing: 12) {
              SettingsIconView(systemName: "wrench.and.screwdriver.fill", color: .gray)
              Text("デベロッパ")
              Spacer()
              Text(showDebugOverlay ? "ON" : "OFF")
                .foregroundColor(.secondary)
            }
          }
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
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

struct DeveloperSettingsView: View {
  private let recordingFileStore: RecordingFileStoring
  @AppStorage("showDebugOverlay") private var showDebugOverlay = false
  @State private var devCSVFiles: [URL] = []

  init(recordingFileStore: RecordingFileStoring) {
    self.recordingFileStore = recordingFileStore
  }

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $showDebugOverlay) {
          HStack(spacing: 12) {
            SettingsIconView(systemName: "ladybug.fill", color: .gray)
            Text("デバッグ表示")
              .font(.system(size: 16))
          }
        }
        .tint(.green)
      } footer: {
        Text("Detect画面にAI結果、更新間隔、スキップ回数を表示します。")
      }

      Section {
        if devCSVFiles.isEmpty {
          Text("デバッグCSVはまだありません")
            .foregroundColor(.secondary)
        } else {
          ForEach(devCSVFiles, id: \.self) { csvURL in
            NavigationLink(destination: CSVPreviewView(csvURL: csvURL)) {
              Label(csvURL.lastPathComponent, systemImage: "doc.text.fill")
            }
          }
        }
      } header: {
        Text("Debug CSV")
      } footer: {
        Text("Detect画面で保存されたDev_から始まるCSVのみを表示します。")
      }
    }
    .navigationTitle("Developer")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          loadDevCSVFiles()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
      }
    }
    .onAppear {
      loadDevCSVFiles()
    }
  }

  private func loadDevCSVFiles() {
    try? recordingFileStore.prepareStorage()
    // Defaultと各Sceneに保存されたDev CSVを同じ一覧で確認できるようにする。
    devCSVFiles = recordingFileStore.allDevCSVFiles()
      .sorted { lhs, rhs in
        modificationDate(for: lhs) > modificationDate(for: rhs)
      }
  }

  private func modificationDate(for url: URL) -> Date {
    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
    return values?.contentModificationDate ?? .distantPast
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
      AppLogger.audio.error("警告音ファイルが見つかりません: \(fileName).wav")
      return
    }

    do {
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.numberOfLoops = 0
      audioPlayer?.play()
    } catch {
      AppLogger.audio.error("警告音のプレビュー再生に失敗しました: \(error.localizedDescription)")
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
          Text(
            [
              "スピーカーからの音声をリアルタイムで録音します。\n",
              "ハウリング防止のため、",
              "有線イヤホンやヘッドフォンの接続を強く推奨します。",
            ].joined()
          )
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

    }
    .navigationTitle("モニタリング")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)  // タブバーを隠す
  }
}

// MARK: - 音源選択およびプレビュー画面 (子画面)
struct TestSoundSelectionView: View {
  @AppStorage("selectedMonitoringSound") var selectedMonitoringSound: MonitoringSoundSource =
    .sweep5Seconds

  // プレビュー再生用のオーディオプレイヤー
  @State private var audioPlayer: AVAudioPlayer?

  var body: some View {
    Form {
      Section {
        ForEach(MonitoringSoundSource.availableCases) { source in
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
    .navigationTitle("テスト音源")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if !selectedMonitoringSound.isBundled {
        selectedMonitoringSound = .sweep5Seconds
      }
    }
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
      AppLogger.audio.error("モニタリング音源が見つかりません: \(fileName).wav")
      return
    }

    do {
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.numberOfLoops = 0  // ループなし（1回のみ）
      audioPlayer?.play()
    } catch {
      AppLogger.audio.error("音源のプレビュー再生に失敗しました: \(error.localizedDescription)")
    }
  }
}
