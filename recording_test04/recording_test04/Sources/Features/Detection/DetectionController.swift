import AVFoundation
import CoreML
import Foundation
import Observation
import SwiftUI

enum DetectionState {
  case standby
  case safe
  case uncertain
  case detect

  var title: String {
    switch self {
    case .standby: return "Standby"
    case .safe: return "Safe"
    case .uncertain: return "Uncertain"
    case .detect: return "Detect"
    }
  }
  var themeColor: Color {
    switch self {
    case .standby: return .secondary
    case .safe: return .green
    case .uncertain: return .orange
    case .detect: return .red
    }
  }
}

enum LocalizationState: String {
  case listeningForBeep
  case waitingAfterBeep
  case collectingAudio
  case predicting
}

enum DetectionCSVHeader {
  static let measurement = [
    "elapsed_time", "speed_kmh", "volume_db", "status", "ai_angle",
    "ai_probability", "ground_truth_angle", "direction_tag", "device_orientation", "mic_source",
    "buffer_count", "feature_created", "predict_executed", "predict_success",
  ].joined(separator: ",")

  static let development = [
    "elapsed_time", "speed_kmh", "volume_db", "status", "ai_angle",
    "ai_probability", "ground_truth_angle", "direction_tag", "device_orientation", "mic_source",
    "update_ms", "feature_skip_count", "prediction_skip_count", "beep_detected_count",
    "beep_detected_this_frame", "last_beep_elapsed_time", "beep_to_prediction_ms",
    "localization_state", "buffer_count", "feature_created", "predict_executed",
    "predict_success", "debug_message",
  ].joined(separator: ",")

  static let localization = [
    "event_id", "model_name", "elapsed_time", "ground_truth_angle", "direction_tag",
    "predicted_angle",
    "max_probability", "accepted", "prob_000", "prob_045", "prob_090", "prob_135",
    "prob_180", "prob_225", "prob_270", "prob_315", "beep_detected_time",
    "prediction_completed_time", "beep_to_prediction_ms", "warning_triggered",
    "prediction_success",
  ].joined(separator: ",")
}

// MARK: - 1. Detecting (検知ロジック)
@Observable
final class DetectionController {
  let recordingFileStore: RecordingFileStoring
  let audioIOController: AudioIOController
  let audioEngine = AVAudioEngine()
  var audioFile: AVAudioFile?
  var testSoundPlayer: AVAudioPlayer?
  var testSoundPlaybackTask: Task<Void, Never>?
  // Core MLの特徴量抽出は44.1kHz / stereo / Float32を前提にしている。
  let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 44100,
    channels: 2,
    interleaved: false
  )!

  let featureExtractor = AudioFeatureExtractor()
  let mlManager = DirectionModelService()
  let beepDetector = BeepDetector()
  let featureExtractionQueue = DispatchQueue(
    label: "dev.tuist.recording-test04.feature-extraction",
    qos: .userInitiated
  )

  var isRecording = false
  private var isAudioConfigurationLocked = false
  var isTestSoundPlaying = false
  var state: DetectionState = .standby
  var elapsedTime: TimeInterval = 0.0
  var currentDecibel: Float = -160.0

  var currentAIAngle: Int?
  var currentAIProbability: Float = 0.0
  var currentDirectionProbabilities: [Float] = Array(repeating: 0.0, count: 8)
  var currentGroundTruth: String = "FalseDetect"  // ピッカー選択値
  var currentDirectionTag = ""
  var warningTriggerID: Int = 0

  // ===== デバッグ情報 =====
  var debugBufferCount: Int = 0
  var debugFeatureCreated: Bool = false
  var debugPredictExecuted: Bool = false
  var debugPredictSuccess: Bool = false
  var debugMessage: String = ""
  var debugLastUpdateMs: Double = 0.0
  var debugFeatureSkipCount: Int = 0
  var debugPredictionSkipCount: Int = 0
  var debugBeepDetectedCount: Int = 0
  var debugBeepDetectedThisFrame: Bool = false
  var debugLocalizationState: String = LocalizationState.listeningForBeep.rawValue
  var debugLastBeepElapsedTime: Double = 0.0
  var debugBeepToPredictionMs: Double = 0.0

  var timer: Timer?
  var startTime: Date?
  var speedcsvTimer: Timer?
  var speedcsvData: [String] = []
  var devcsvData: [String] = []
  var eventcsvData: [String] = []
  var currentBaseFileName: String = ""
  var currentRecordingDirectory: URL?
  var currentOrientation: String = "横"
  var currentMicSource: String = "背面"
  let featureExtractionLock = NSLock()
  var isExtractingFeatures = false
  let predictionLock = NSLock()
  var isPredicting = false
  var lastPredictionSuccessTime: Date?
  // ビープ音そのものを定位対象にするため、検知後の待機は入れない。
  let localizationDelaySeconds: TimeInterval = 0.0
  let preRollSamples: Int = 22050
  var preRollL: [Float] = []
  var preRollR: [Float] = []
  var localizationState: LocalizationState = .listeningForBeep
  var beepDetectedAt: Date?
  var pendingEventID: Int?
  var pendingGroundTruth: String = "FalseDetect"
  var nextEventID: Int = 1
  var resultClearTask: Task<Void, Never>?
  var isWarningArmed = true
  let resultDisplaySeconds: TimeInterval = 3.0

  init(
    recordingFileStore: RecordingFileStoring,
    audioIOController: AudioIOController
  ) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
  }

  @MainActor
  func startDetecting(
    locationManager: LocationService,
    orientation: String,
    micSource: String,
    directionTag: MeasurementDirectionTag
  ) {
    self.currentOrientation = orientation
    self.currentMicSource = micSource
    self.currentDirectionTag = directionTag.rawValue
    self.currentGroundTruth = directionTag == .none ? "FalseDetect" : directionTag.rawValue
    let audioSession = AVAudioSession.sharedInstance()

    do {
      // WAVと2種類のCSVが同じSceneへ保存されるよう、開始時のURLを保持する。
      let recordingFile = try recordingFileStore.makeRecordingURL(prefix: "Detecting")
      self.currentBaseFileName = recordingFile.baseName
      self.currentRecordingDirectory = recordingFile.url.deletingLastPathComponent()
      let audioFilename = recordingFile.url

      try audioSession.setCategory(
        .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
      try audioSession.setPreferredSampleRate(targetFormat.sampleRate)
      if audioSession.maximumInputNumberOfChannels >= targetFormat.channelCount {
        try audioSession.setPreferredInputNumberOfChannels(Int(targetFormat.channelCount))
      }
      try audioSession.setActive(true)
      try configureInputSession(audioSession, orientation: orientation, micSource: micSource)

      let inputNode = audioEngine.inputNode
      let inputFormat = inputNode.inputFormat(forBus: 0)
      guard let audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
        AppLogger.audio.error("Audio Converterの作成に失敗しました")
        return
      }

      audioFile = try AVAudioFile(forWriting: audioFilename, settings: targetFormat.settings)

      inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
        [weak self] (buffer, time) in
        guard let self = self else { return }
        guard
          let convertedBuffer = self.convertBuffer(
            buffer,
            converter: audioConverter,
            targetFormat: self.targetFormat
          )
        else {
          return
        }

        do {
          try self.audioFile?.write(from: convertedBuffer)
        } catch {
          AppLogger.storage.error("検知音声の書き込みに失敗しました: \(error.localizedDescription)")
        }

        self.calculateDecibel(buffer: convertedBuffer)
        self.handleLocalizationAudio(buffer: convertedBuffer, at: Date())
      }

      audioEngine.prepare()
      try audioEngine.start()

      lockAudioConfiguration()
      isRecording = true
      state = .safe
      elapsedTime = 0.0
      startTime = Date()
      featureExtractor.reset()
      beepDetector.reset()
      resetPreRollBuffer()
      setLocalizationState(.listeningForBeep)
      resetDebugMetrics()
      resultClearTask?.cancel()
      resultClearTask = nil
      currentAIAngle = nil
      currentAIProbability = 0.0
      currentDirectionProbabilities = Array(repeating: 0.0, count: 8)
      pendingEventID = nil
      pendingGroundTruth = "FalseDetect"
      nextEventID = 1
      isWarningArmed = true

      speedcsvData = [DetectionCSVHeader.measurement]
      devcsvData = [DetectionCSVHeader.development]
      eventcsvData = [DetectionCSVHeader.localization]

      timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
        guard let self = self, let startTime = self.startTime else { return }
        self.elapsedTime = Date().timeIntervalSince(startTime)
      }
      speedcsvTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        self?.recordCSVLog(locationManager: locationManager)
        self?.recordDevCSVLog(locationManager: locationManager)
      }

    } catch {
      AppLogger.audio.error("検知録音の開始に失敗しました: \(error.localizedDescription)")
    }
  }

  @MainActor
  func stopDetecting() {
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    audioFile = nil
    isRecording = false
    unlockAudioConfiguration()
    state = .standby

    timer?.invalidate()
    speedcsvTimer?.invalidate()
    resultClearTask?.cancel()
    resultClearTask = nil
    // Sceneが例外的に消失していた場合は、CSVだけでもDefaultへ退避する。
    if let directory = currentRecordingDirectory,
      !recordingFileStore.directoryExists(at: directory)
    {
      do {
        try recordingFileStore.prepareStorage()
      } catch {
        AppLogger.storage.error("Default保存先の復旧に失敗しました: \(error.localizedDescription)")
      }
      currentRecordingDirectory = recordingFileStore.defaultDirectory
    }
    savespeedCSV()
    saveDevCSV()
    saveEventCSV()
    featureExtractor.reset()
    beepDetector.reset()
    resetPreRollBuffer()
    beepDetectedAt = nil
    pendingEventID = nil
    setLocalizationState(.listeningForBeep)
    resetDetectionDisplay()
  }

  @MainActor
  private func lockAudioConfiguration() {
    guard !isAudioConfigurationLocked else { return }
    audioIOController.lockConfiguration()
    isAudioConfigurationLocked = true
  }

  @MainActor
  private func unlockAudioConfiguration() {
    guard isAudioConfigurationLocked else { return }
    audioIOController.unlockConfiguration()
    isAudioConfigurationLocked = false
  }

}
