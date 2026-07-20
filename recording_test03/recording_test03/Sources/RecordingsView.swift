import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct RecordingsView_Previews: PreviewProvider {
  static var previews: some View {
    RecordingsView()
  }
}

// MARK: - 1. AudioRecorder (録音ロジック)
@Observable
class AudioRecorder {
  var audioRecorder: AVAudioRecorder?
  private var audioPlayer: AVAudioPlayer?

  var isRecording = false
  var elapsedTime: TimeInterval = 0.0
  var measurementStatus: String = "待機中"

  // L/Rそれぞれの音量データ
  var leftDecibel: Float = 0.0
  var rightDecibel: Float = 0.0
  var leftLevel: CGFloat = 0.0
  var rightLevel: CGFloat = 0.0

  private var timer: Timer?
  private var levelTimer: Timer?
  private var startTime: Date?
  private var currentBaseFileName: String = ""
  private var currentRecordingURL: URL?
  private var measurementTask: Task<Void, Never>?
  private var statusResetTask: Task<Void, Never>?
  private var activeInputChannelCount = 0

  private enum RecordingStartError: LocalizedError {
    case monitoringSoundNotFound(String)
    case monitoringSoundCannotPlay(String)
    case builtInMicUnavailable
    case micDataSourceUnavailable(String)
    case stereoPolarPatternUnavailable
    case stereoInputUnavailable(Int)

    var errorDescription: String? {
      switch self {
      case .monitoringSoundNotFound(let fileName):
        return "\(fileName).wav が見つかりません"
      case .monitoringSoundCannotPlay(let fileName):
        return "\(fileName).wav を再生できません"
      case .builtInMicUnavailable:
        return "内蔵マイクを選択できません"
      case .micDataSourceUnavailable(let micSource):
        return "\(micSource)マイクを選択できません"
      case .stereoPolarPatternUnavailable:
        return "ステレオ入力に対応していません"
      case .stereoInputUnavailable(let channelCount):
        return "ステレオ入力を開始できません: 入力 \(channelCount)ch"
      }
    }
  }

  func startRecording(orientation: String, micSource: String, prefix: String = "Recording") {
    let audioSession = AVAudioSession.sharedInstance()
    let isMonitoringRecording = prefix == "Monitoring"
    let outputRawValue =
      UserDefaults.standard.string(forKey: "selectedOutputDevice")
      ?? OutputDeviceOption.speaker.rawValue
    let outputDevice = OutputDeviceOption(rawValue: outputRawValue) ?? .speaker

    do {
      // 録音開始時点のSceneと連番を固定し、録音中の設定変更から保存先を切り離す。
      let recordingFile = try RecordingFileStore.shared.makeRecordingURL(prefix: prefix)
      self.currentBaseFileName = recordingFile.baseName
      let audioFilename = recordingFile.url
      self.currentRecordingURL = audioFilename

      measurementTask?.cancel()
      statusResetTask?.cancel()
      audioPlayer?.stop()
      audioPlayer = nil

      // Monitoringでは設定画面の再生デバイス指定に合わせて出力経路を分ける。
      // Bluetooth再生時に.defaultToSpeakerを同時指定すると、経路選択が曖昧になりやすい。
      let sessionOptions: AVAudioSession.CategoryOptions =
        outputDevice == .external
        ? [.allowBluetoothA2DP]
        : [.defaultToSpeaker]
      try audioSession.setCategory(
        .playAndRecord, mode: .default, options: sessionOptions)
      try audioSession.setActive(true)
      if outputDevice == .speaker {
        try audioSession.overrideOutputAudioPort(.speaker)
      } else {
        try audioSession.overrideOutputAudioPort(.none)
      }

      if isMonitoringRecording {
        let soundRawValue =
          UserDefaults.standard.string(forKey: "selectedMonitoringSound")
          ?? MonitoringSoundSource.sweep_5s.rawValue
        let soundSource = MonitoringSoundSource(rawValue: soundRawValue) ?? .sweep_5s

        guard let soundUrl = Bundle.main.url(forResource: soundSource.fileName, withExtension: "wav") else {
          throw RecordingStartError.monitoringSoundNotFound(soundSource.fileName)
        }

        do {
          audioPlayer = try AVAudioPlayer(contentsOf: soundUrl)
          audioPlayer?.numberOfLoops = 0
          audioPlayer?.volume = 1.0
          // 再生開始時の遅延を抑え、録音と再生の経路を開始前に確定させる。
          audioPlayer?.prepareToPlay()
        } catch {
          throw RecordingStartError.monitoringSoundCannotPlay(soundSource.fileName)
        }
      }

      // 録音マイク（前面/背面）とステレオ設定
      guard let availableInputs = audioSession.availableInputs,
        let builtInMic = availableInputs.first(where: { $0.portType == .builtInMic })
      else {
        throw RecordingStartError.builtInMicUnavailable
      }

      let targetOrientation: AVAudioSession.Orientation = (micSource == "背面") ? .back : .front
      guard let selectedDataSource = builtInMic.dataSources?.first(where: {
        $0.orientation == targetOrientation
      }) else {
        throw RecordingStartError.micDataSourceUnavailable(micSource)
      }

      // 対象のマイク(前面/背面)をハードウェアにセット
      try builtInMic.setPreferredDataSource(selectedDataSource)

      // ステレオ非対応の入力では定位用データとして扱えないため、録音開始前に失敗扱いにする。
      guard let supportedPatterns = selectedDataSource.supportedPolarPatterns,
        supportedPatterns.contains(.stereo)
      else {
        throw RecordingStartError.stereoPolarPatternUnavailable
      }
      try selectedDataSource.setPreferredPolarPattern(.stereo)
      print("ステレオ入力を適用しました")

      // デバイス全体にこのマイク入力を適用
      try audioSession.setPreferredInput(builtInMic)
      print("マイク設定: \(micSource) を選択")

      // stereo polar patternと入力ポートを確定した後で2chを要求する。
      // 要求前にmaximumInputNumberOfChannelsを見ると、未確定の経路で1ch判定になる場合がある。
      guard audioSession.maximumInputNumberOfChannels >= 2 else {
        throw RecordingStartError.stereoInputUnavailable(audioSession.maximumInputNumberOfChannels)
      }
      try audioSession.setPreferredInputNumberOfChannels(2)

      // 端末の向き設定を反映（必ずマイク設定の「後」に行う）
      if orientation == "縦" {
        try audioSession.setPreferredInputOrientation(.portrait)
      } else {
        try audioSession.setPreferredInputOrientation(.landscapeRight)
      }

      // 録音フォーマット設定（ステレオ 44.1kHz 16bit PCM）
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]

      // 録音開始
      print("録音開始: \(audioFilename.lastPathComponent)")
      audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
      audioRecorder?.isMeteringEnabled = true
      // AVAudioRecorder作成直後のformat.channelCountはBluetooth出力時に1chを返す場合がある。
      // 録音は2ch設定で要求し、実ファイルが2chかどうかはstopRecording後に検査する。
      activeInputChannelCount = 2

      isRecording = true
      elapsedTime = 0.0
      startTime = Date()
      measurementStatus = isMonitoringRecording ? "テスト音再生中" : "録音中"

      // 時間計測タイマー
      timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
        guard let self = self, let startTime = self.startTime else { return }
        self.elapsedTime = Date().timeIntervalSince(startTime)
      }

      if isMonitoringRecording {
        // Monitoringも2ch設定で録音を開始し、保存後に実ファイルのチャンネル数を確認する。
        measurementTask = Task {
          audioRecorder?.record()

          await MainActor.run {
            self.startMonitoring()
          }

          let duration = audioPlayer?.duration ?? 0
          audioPlayer?.play()

          try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
          if Task.isCancelled { return }

          await MainActor.run {
            self.stopRecording()
          }
        }
      } else {
        audioRecorder?.record()
        startMonitoring()
      }

    } catch {
      print("エラー: \(error.localizedDescription)")
      audioRecorder?.stop()
      audioPlayer?.stop()
      audioRecorder = nil
      audioPlayer = nil
      measurementTask?.cancel()
      statusResetTask?.cancel()
      timer?.invalidate()
      levelTimer?.invalidate()
      activeInputChannelCount = 0
      currentRecordingURL = nil
      isRecording = false
      measurementStatus = error.localizedDescription
    }
  }

  func stopRecording() {
    let recordedURL = currentRecordingURL

    measurementTask?.cancel()
    statusResetTask?.cancel()
    audioRecorder?.stop()
    audioPlayer?.stop()
    isRecording = false
    timer?.invalidate()
    levelTimer?.invalidate()
    measurementStatus = "待機中"
    elapsedTime = 0.0
    leftLevel = 0.0
    rightLevel = 0.0
    leftDecibel = 0.0
    rightDecibel = 0.0
    activeInputChannelCount = 0
    currentRecordingURL = nil

    if let recordedURL, !isStereoRecordingFile(recordedURL) {
      try? FileManager.default.removeItem(at: recordedURL)
      measurementStatus = "ステレオ録音未成立"
      // 失敗理由を見逃さないよう、一定時間だけステータス表示を保持する。
      statusResetTask = Task {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if Task.isCancelled { return }

        await MainActor.run {
          if !self.isRecording && self.measurementStatus == "ステレオ録音未成立" {
            self.measurementStatus = "待機中"
          }
        }
      }
    }
  }

  private func startMonitoring() {
    levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self = self, let recorder = self.audioRecorder else { return }
      recorder.updateMeters()

      // L(0) と R(1) のパワーを取得
      self.leftDecibel = recorder.averagePower(forChannel: 0)
      guard self.activeInputChannelCount >= 2 else {
        self.rightDecibel = 0.0
        self.leftLevel = self.normalizeSoundLevel(level: self.leftDecibel)
        self.rightLevel = 0.0
        return
      }
      self.rightDecibel = recorder.averagePower(forChannel: 1)

      // 表示用に 0.0~1.0 に正規化
      self.leftLevel = self.normalizeSoundLevel(level: self.leftDecibel)
      self.rightLevel = self.normalizeSoundLevel(level: self.rightDecibel)
    }
  }

  private func normalizeSoundLevel(level: Float) -> CGFloat {
    let minDb: Float = -60.0
    if level < minDb { return 0.01 }
    if level >= 0.0 { return 1.0 }
    return CGFloat((level - minDb) / abs(minDb))
  }

  private func isStereoRecordingFile(_ url: URL) -> Bool {
    do {
      let file = try AVAudioFile(forReading: url)
      return file.fileFormat.channelCount == 2
    } catch {
      print("録音ファイル確認エラー: \(error.localizedDescription)")
      return false
    }
  }
}

// MARK: - 2. RecordingsView (UI)
struct RecordingsView: View {
  @State private var audioRecorder = AudioRecorder()
  @Environment(\.verticalSizeClass) var verticalSizeClass

  @AppStorage("deviceOrientation") private var selectedOrientation: String = "横"
  @AppStorage("micSource") private var selectedMicSource: String = "背面"
  @AppStorage(RecordingFileStore.selectedSceneKey) private var selectedScene = RecordingFileStore.defaultSceneName
  @State private var availableScenes: [String] = []

  var body: some View {
    NavigationStack {
      ZStack {
        // 背景色
        Color(UIColor.systemGroupedBackground).ignoresSafeArea()

        if verticalSizeClass == .compact {
          // 【横画面レイアウト】
          GeometryReader { geometry in
            let bottomPadding = geometry.safeAreaInsets.bottom + 16
            let meterWidth = min(220, max(160, geometry.size.width * 0.28))

            HStack(spacing: 30) {
              VStack(spacing: 10) {
                timeDisplay
                recordingStatus
                Spacer()
                recordButton
                  .padding(.bottom, bottomPadding)
                Spacer()
              }
              .frame(width: (geometry.size.width - 30) / 3)

              VStack(spacing: 10) {
                micAssignmentLabels
                  .padding(.top, -12)
                sceneDestinationPicker
                horizontalStereoMeters(width: meterWidth, height: 24)
                // Spacer()
              }
              .padding(.bottom, bottomPadding)
              .frame(width: (geometry.size.width - 30) * 2 / 3)
            }
            .frame(maxHeight: .infinity)
          }
          .padding()
        } else {
          // 【縦画面レイアウト】
          GeometryReader { geometry in
            // MonitoringsViewと同じ配置にし、余った縦方向の領域をステレオメーターの高さに回す。
            let meterHeight = min(220, max(180, geometry.size.height * 0.25))

            VStack(spacing: 10) {
              timeDisplay
              recordingStatus
              micAssignmentLabels
              sceneDestinationPicker
              verticalStereoMeters(height: meterHeight)
              Spacer(minLength: 4)
              recordButton
            }
            .padding(.top, 4)
            .padding(.horizontal)
            .padding(.bottom, 72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      .navigationTitle("Recordings")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear { refreshScenes() }
    }
  }

  // MARK: - 4. Component
  // 時間表示
  private var timeDisplay: some View {
    Text(formatElapsedTime(audioRecorder.elapsedTime))
      .font(.system(size: 48, weight: .thin))
      .monospacedDigit()
  }

  // 録音状態の表示
  private var recordingStatus: some View {
    Text(audioRecorder.isRecording ? "録音中" : "待機中")
      .font(.headline)
      .foregroundColor(audioRecorder.isRecording ? .red : .secondary)
      .padding(.vertical, 6)
      .padding(.horizontal, 16)
      .background(Capsule().fill(Color.primary.opacity(0.1)))
  }

  // マイクの割り当て表示
  private var micAssignmentLabels: some View {
    List {
      Section(header: Text("Mic Assignment")) {
        HStack {
          // 1. 左側: マイク設定
          VStack(spacing: 6) {
            Text(selectedMicSource == "背面" ? "Back" : "Front")
            Divider()
              .overlay(Color.gray)
              .padding(.horizontal, 10)
            Text("Bottom")
          }
          .frame(maxWidth: .infinity)
          Spacer()

          Divider()
            .overlay(Color.gray)

          // 3. 右側: 端末の向き
          VStack(spacing: 6) {
            Image(systemName: selectedOrientation == "縦" ? "iphone" : "iphone.landscape")
              .font(.title2)
            Text(selectedOrientation == "縦" ? "Portrait" : "Landscape")
              .font(.caption)
          }
          .frame(maxWidth: .infinity)
        }
        // .padding(.vertical, 4)
      }
    }
    .listStyle(.insetGrouped)
    .frame(height: 125)
    .scrollDisabled(true)  //
    .scrollContentBackground(.hidden)
  }

  // 保存先はMonitoringsViewと同じUIにする。
  private var sceneDestinationPicker: some View {
    Menu {
      Picker("保存先", selection: $selectedScene) {
        Text(RecordingFileStore.defaultSceneName).tag(RecordingFileStore.defaultSceneName)
        ForEach(availableScenes, id: \.self) { scene in
          Text(scene).tag(scene)
        }
      }
    } label: {
      HStack {
        Text("保存先")
          .foregroundStyle(.black)
        Spacer()
        Text(selectedScene)
          .foregroundStyle(.black)
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.black.opacity(0.55))
      }
      .padding(.horizontal, 16)
      .frame(height: 44)
      .background(Color(UIColor.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .padding(.horizontal)
  }

  private func refreshScenes() {
    do {
      try RecordingFileStore.shared.prepareStorage()
      availableScenes = RecordingFileStore.shared.sceneDirectories().map(\.lastPathComponent)
      if selectedScene != RecordingFileStore.defaultSceneName
        && !availableScenes.contains(selectedScene)
      {
        selectedScene = RecordingFileStore.defaultSceneName
      }
    } catch {
      selectedScene = RecordingFileStore.defaultSceneName
      availableScenes = []
    }
  }

  // ステレオメーター部分(縦画面)
  private func verticalStereoMeters(height: CGFloat) -> some View {
    HStack(spacing: 50) {
      VStack {
        VerticaldBMeter(
          level: audioRecorder.leftLevel, label: "L", font: .system(.caption), height: height)
        Text("\(Int(audioRecorder.leftDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
      VStack {
        VerticaldBMeter(
          level: audioRecorder.rightLevel, label: "R", font: .system(.caption), height: height)
        Text("\(Int(audioRecorder.rightDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
    }
  }

  // ステレオメーター部分(横画面)
  private func horizontalStereoMeters(width: CGFloat, height: CGFloat) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 15) {
        HorizontaldBMeter(
          level: audioRecorder.leftLevel,
          label: "L",
          width: width,
          height: height,
          font: .system(.caption)
        )
        Text("\(Int(audioRecorder.leftDecibel)) dB")
          .font(.system(.subheadline))
          .monospacedDigit()
          .frame(width: 64, alignment: .leading)
      }
      HStack(spacing: 15) {
        HorizontaldBMeter(
          level: audioRecorder.rightLevel,
          label: "R",
          width: width,
          height: height,
          font: .system(.caption)
        )
        Text("\(Int(audioRecorder.rightDecibel)) dB")
          .font(.system(.subheadline))
          .monospacedDigit()
          .frame(width: 64, alignment: .leading)
      }
    }
  }

  // 録音ボタン
  private var recordButton: some View {
    Button(action: {
      if audioRecorder.isRecording {
        audioRecorder.stopRecording()
      } else {
        // @AppStorage で読み込んだ設定値を渡して録音を開始
        audioRecorder.startRecording(
          orientation: selectedOrientation,
          micSource: selectedMicSource,
          prefix: "Recording" //録音ファイルの接頭辞は "Recording" に固定
        )
      }
    }) {
      ZStack {
        Circle()
          .strokeBorder(Color.primary.opacity(0.2), lineWidth: 4)
          .frame(width: 70, height: 70)
        if audioRecorder.isRecording {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.red)
            .frame(width: 30, height: 30)
        } else {
          Circle()
            .fill(Color.red)
            .frame(width: 60, height: 60)
        }
      }
    }
  }

  private func formatElapsedTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
    return String(format: "%02d:%02d.%02d", minutes, seconds, ms)
  }
}

// 垂直メーターのコンポーネント
struct VerticaldBMeter: View {
  var level: CGFloat
  var label: String
  var font: Font = .headline
  var width: CGFloat = 56  // 主要画面で圧迫しない幅に抑える
  var height: CGFloat = 150  // 画面構成に応じて高さだけ調整可能にする

  var body: some View {
    VStack(spacing: 8) {
      Text(label).font(font).foregroundColor(.secondary)
      ZStack(alignment: .bottom) {
        // 背景の溝
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.primary.opacity(0.1))
          .frame(width: width, height: height)

        // 音量レベル（グラデーション）
        RoundedRectangle(cornerRadius: 6)
          .fill(
            LinearGradient(
              gradient: Gradient(colors: [.red, .white]), startPoint: .top,
              endPoint: .bottom)
          )
          .frame(width: width, height: height * level)
          .animation(.spring(response: 0.15, dampingFraction: 0.8), value: level)
      }
    }
  }
}

// 水平メーターのコンポーネント
struct HorizontaldBMeter: View {
  var level: CGFloat
  var label: String
  var width: CGFloat = 240  // 横画面でも操作ボタンや設定欄を圧迫しない幅に抑える
  var height: CGFloat = 32
  var font: Font = .headline

  var body: some View {
    HStack(spacing: 8) {
      Text(label).font(font).foregroundColor(.secondary)
      ZStack(alignment: .leading) {
        // 背景の溝
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.primary.opacity(0.1))
          .frame(width: width, height: height)

        // 音量レベル（グラデーション）
        RoundedRectangle(cornerRadius: 6)
          .fill(
            LinearGradient(
              gradient: Gradient(colors: [.white, .red]), startPoint: .leading,
              endPoint: .trailing)
          )
          .frame(width: width * level, height: height)
          .animation(.spring(response: 0.15, dampingFraction: 0.8), value: level)
      }
    }
  }
}
