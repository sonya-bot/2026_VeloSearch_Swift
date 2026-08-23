import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct RecordingView_Previews: PreviewProvider {
  static var previews: some View {
    RecordingView(
      recordingFileStore: RecordingFileStore.shared,
      userDefaults: .standard,
      audioIOController: AudioIOController()
    )
  }
}

// MARK: - 1. AudioRecordingController (録音ロジック)
@Observable
@MainActor
final class AudioRecordingController {
  private let recordingFileStore: RecordingFileStoring
  private let userDefaults: UserDefaults
  private let audioIOController: AudioIOController

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
  private(set) var activeInputChannelCount = 2
  private var directionTag: String?
  private var recordingPrefix = "Recording"
  private var recordingFinished: (() -> Void)?

  init(
    recordingFileStore: RecordingFileStoring,
    userDefaults: UserDefaults,
    audioIOController: AudioIOController
  ) {
    self.recordingFileStore = recordingFileStore
    self.userDefaults = userDefaults
    self.audioIOController = audioIOController
  }

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

  func startRecording(
    orientation: String,
    micSource: String,
    prefix: String = "Recording",
    directionTag: String? = nil,
    onFinished: (() -> Void)? = nil
  ) {
    let isMonitoringRecording = prefix == "Monitoring"
    let outputRawValue =
      userDefaults.string(forKey: "selectedOutputDevice")
      ?? OutputDeviceOption.speaker.rawValue
    let outputDevice = OutputDeviceOption(rawValue: outputRawValue) ?? .speaker

    do {
      // 録音開始時点のSceneと連番を固定し、録音中の設定変更から保存先を切り離す。
      let recordingFile = try recordingFileStore.makeRecordingURL(prefix: prefix)
      self.currentBaseFileName = recordingFile.baseName
      let audioFilename = recordingFile.url
      self.currentRecordingURL = audioFilename
      self.directionTag = directionTag
      self.recordingPrefix = prefix
      self.recordingFinished = onFinished

      measurementTask?.cancel()
      statusResetTask?.cancel()
      audioPlayer?.stop()
      audioPlayer = nil

      _ = outputDevice
      let audioConfiguration = try audioIOController.configureForRecording(
        allowsPlayback: isMonitoringRecording
      )

      if isMonitoringRecording {
        let soundRawValue =
          userDefaults.string(forKey: "selectedMonitoringSound")
          ?? MonitoringSoundSource.sweep5Seconds.rawValue
        let storedSoundSource =
          MonitoringSoundSource(rawValue: soundRawValue) ?? .sweep5Seconds
        let soundSource = storedSoundSource.isBundled ? storedSoundSource : .sweep5Seconds

        guard
          let soundUrl = Bundle.main.url(forResource: soundSource.fileName, withExtension: "wav")
        else {
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

      _ = orientation
      _ = micSource

      // 録音フォーマット設定（ステレオ 44.1kHz 16bit PCM）
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: audioConfiguration.channelCount,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]

      // 録音開始
      audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
      audioRecorder?.isMeteringEnabled = true
      activeInputChannelCount = audioConfiguration.channelCount

      isRecording = true
      elapsedTime = 0.0
      startTime = Date()
      measurementStatus = isMonitoringRecording ? "テスト音再生中" : "録音中"

      // 時間計測タイマー
      timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self, let startTime = self.startTime else { return }
          self.elapsedTime = Date().timeIntervalSince(startTime)
        }
      }

      if isMonitoringRecording {
        // Monitoringも2ch設定で録音を開始し、
        // 保存後に実ファイルのチャンネル数を確認する。
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
      AppLogger.audio.error("録音の開始に失敗しました: \(error.localizedDescription)")
      audioRecorder?.stop()
      audioPlayer?.stop()
      audioRecorder = nil
      audioPlayer = nil
      measurementTask?.cancel()
      statusResetTask?.cancel()
      timer?.invalidate()
      levelTimer?.invalidate()
      activeInputChannelCount = 1
      currentRecordingURL = nil
      isRecording = false
      measurementStatus = error.localizedDescription
    }
  }

  func stopRecording() {
    let recordedURL = currentRecordingURL
    let expectedChannelCount = activeInputChannelCount
    let completion = recordingFinished

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
    recordingFinished = nil
    currentRecordingURL = nil

    if let recordedURL, !hasExpectedChannelCount(recordedURL, expected: expectedChannelCount) {
      try? FileManager.default.removeItem(at: recordedURL)
      measurementStatus = "録音形式不一致"
      // 失敗理由を見逃さないよう、一定時間だけステータス表示を保持する。
      statusResetTask = Task {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if Task.isCancelled { return }

        await MainActor.run {
          if !self.isRecording && self.measurementStatus == "録音形式不一致" {
            self.measurementStatus = "待機中"
          }
        }
      }
      return
    }

    if let recordedURL, recordingPrefix == "Monitoring" {
      writeMonitoringMetadata(for: recordedURL, channelCount: expectedChannelCount)
    }
    completion?()
  }

  private func startMonitoring() {
    levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, let recorder = self.audioRecorder else { return }
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
  }

  private func normalizeSoundLevel(level: Float) -> CGFloat {
    let minDb: Float = -60.0
    if level < minDb { return 0.01 }
    if level >= 0.0 { return 1.0 }
    return CGFloat((level - minDb) / abs(minDb))
  }

  private func hasExpectedChannelCount(_ url: URL, expected: Int) -> Bool {
    do {
      let file = try AVAudioFile(forReading: url)
      return file.fileFormat.channelCount == AVAudioChannelCount(expected)
    } catch {
      AppLogger.audio.error("録音ファイルの確認に失敗しました: \(error.localizedDescription)")
      return false
    }
  }

  private func writeMonitoringMetadata(for audioURL: URL, channelCount: Int) {
    let configuration = audioIOController.activeConfiguration
    let metadata = MonitoringMeasurementMetadata(
      recordedAt: Date(),
      directionTag: directionTag,
      inputDevice: configuration.inputName,
      outputDevice: configuration.outputName,
      sampleRate: configuration.sampleRate,
      channelCount: channelCount,
      channelLabels: channelCount >= 2
        ? (configuration.isBuiltInInput
          ? [configuration.micSource == .back ? "Back" : "Front", "Bottom"]
          : ["Left", "Right"])
        : ["Mono"]
    )
    let metadataURL = audioURL.deletingPathExtension().appendingPathExtension("json")
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
    } catch {
      AppLogger.storage.error("Monitoringメタデータの保存に失敗しました: \(error.localizedDescription)")
    }
  }
}

private struct MonitoringMeasurementMetadata: Encodable {
  let recordedAt: Date
  let directionTag: String?
  let inputDevice: String
  let outputDevice: String
  let sampleRate: Double
  let channelCount: Int
  let channelLabels: [String]
}

// MARK: - 2. RecordingView (UI)
struct RecordingView: View {
  private let recordingFileStore: RecordingFileStoring
  @ObservedObject private var audioIOController: AudioIOController
  @State private var audioRecorder: AudioRecordingController
  @Environment(\.verticalSizeClass) var verticalSizeClass

  @AppStorage("deviceOrientation") private var selectedOrientation: String = "横"
  @AppStorage("micSource") private var selectedMicSource: String = "背面"
  @AppStorage(RecordingFileStore.selectedSceneKey) private var selectedScene = RecordingFileStore
    .defaultSceneName

  init(
    recordingFileStore: RecordingFileStoring,
    userDefaults: UserDefaults,
    audioIOController: AudioIOController
  ) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
    _audioRecorder = State(
      initialValue: AudioRecordingController(
        recordingFileStore: recordingFileStore,
        userDefaults: userDefaults,
        audioIOController: audioIOController
      )
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        // 背景色
        Color(UIColor.systemGroupedBackground).ignoresSafeArea()

        if verticalSizeClass == .compact {
          // 【横画面レイアウト】
          MeasurementLandscapeLayout { _ in
            VStack(spacing: 10) {
              timeDisplay
              recordingStatus
              Spacer(minLength: 0)
              recordButton
              Spacer(minLength: 0)
            }
          } trailingContent: { availableSize in
            let meterWidth = min(340, max(150, availableSize.width * 0.36))
            VStack(spacing: 8) {
              AudioRouteStatusButton(audioIOController: audioIOController)
              MeasurementDestinationPicker(
                recordingFileStore: recordingFileStore,
                selection: $selectedScene,
                isDisabled: audioRecorder.isRecording
              )
              horizontalStereoMeters(width: meterWidth, height: 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
          }
        } else {
          // 【縦画面レイアウト】
          GeometryReader { geometry in
            // MonitoringViewと同じ配置にし、
            // 余った縦方向の領域をステレオメーターの高さに回す。
            let meterHeight = min(210, max(120, geometry.size.height * 0.24))

            VStack(spacing: 10) {
              AudioRouteStatusButton(audioIOController: audioIOController)
              MeasurementDestinationPicker(
                recordingFileStore: recordingFileStore,
                selection: $selectedScene,
                isDisabled: audioRecorder.isRecording
              )
              VStack(spacing: 8) {
                timeDisplay
                recordingStatus
                verticalStereoMeters(height: meterHeight)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(Color(uiColor: .secondarySystemGroupedBackground))
              .clipShape(RoundedRectangle(cornerRadius: 16))
              recordButton
            }
            .padding(.top, 4)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      .navigationTitle("Recordings")
      .navigationBarTitleDisplayMode(.inline)
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

  private var audioConfigurationIssue: String? {
    audioIOController.configurationIssue()
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
      if audioRecorder.activeInputChannelCount >= 2 {
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
      if audioRecorder.activeInputChannelCount >= 2 {
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
  }

  // 録音ボタン
  private var recordButton: some View {
    MeasurementControlButton(
      idleTitle: "Record",
      activeTitle: "Stop",
      isActive: audioRecorder.isRecording,
      tint: .red,
      isDisabled: !audioRecorder.isRecording && audioConfigurationIssue != nil
    ) {
      if audioRecorder.isRecording {
        audioRecorder.stopRecording()
      } else {
        audioRecorder.startRecording(
          orientation: selectedOrientation,
          micSource: selectedMicSource,
          prefix: "Recording"
        )
      }
    }
    .overlay(alignment: .top) {
      if !audioRecorder.isRecording, let audioConfigurationIssue {
        Text(audioConfigurationIssue)
          .font(.caption2)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .frame(width: 220)
          .offset(y: -32)
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
