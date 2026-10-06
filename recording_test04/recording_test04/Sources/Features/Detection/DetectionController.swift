import AVFoundation
import Combine
import CoreML
import Foundation
import Observation
import SwiftUI

enum DetectionState {
  case standby
  case safe
  case uncertain
  case detect
  case unavailable

  var title: String {
    switch self {
    case .standby: return "Standby"
    case .safe: return "Safe"
    case .uncertain: return "Uncertain"
    case .detect: return "Detect"
    case .unavailable: return "Audio I/O Error"
    }
  }
  var themeColor: Color {
    switch self {
    case .standby: return .secondary
    case .safe: return .green
    case .uncertain: return .orange
    case .detect: return .red
    case .unavailable: return .red
    }
  }
}

enum LocalizationState: String {
  case listeningForBeep
  case collectingAudio
  case predicting
}

enum DetectionCSVHeader {
  static let measurement = [
    "elapsed_time", "speed_kmh", "volume_db", "status", "ai_angle", "ai_probability",
    "ground_truth_angle", "direction_tag", "device_orientation", "mic_source", "update_ms",
    "feature_skip_count", "prediction_skip_count", "beep_detected_count",
    "beep_detected_this_frame",
    "last_beep_elapsed_time", "beep_to_prediction_ms", "localization_state", "buffer_count",
    "feature_created", "predict_executed", "predict_success", "debug_message",
  ].joined(separator: ",")

  static let localization = [
    "event_id", "model_name", "elapsed_time", "ground_truth_angle", "direction_tag",
    "predicted_angle",
    "max_probability", "accepted", "prob_000", "prob_045", "prob_090", "prob_135",
    "prob_180", "prob_225", "prob_270", "prob_315", "beep_detected_time",
    "prediction_completed_time", "beep_to_prediction_ms", "warning_triggered",
    "prediction_success", "audio_collection_ms", "feature_extraction_ms", "inference_ms",
    "ui_update_ms", "total_ms", "audio_ready_time", "feature_started_time",
    "feature_completed_time",
    "prediction_started_time", "inference_completed_time", "ui_updated_time", "device_model",
    "os_version", "app_version", "build_number", "detection_threshold", "csv_schema_version",
    "outcome", "failure_kind",
  ].joined(separator: ",")
}

// MARK: - 1. Detecting (検知ロジック)
@MainActor
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

  var featureExtractor = AudioFeatureExtractor()
  let modelSelection: DirectionModelSelectionController
  let clock: MeasurementClock
  let environment: MeasurementEnvironment
  var activeSessionID: UUID?
  var sessionOrigin: TimeInterval = 0
  var activeEvent: LocalizationEvent?
  var sessionPredictor: DirectionPredicting?
  var sessionModelName = ""
  var modelErrorMessage: String?

  var displayedModelName: String {
    if isRecording { return sessionModelName }
    return modelSelection.selectedModelName ?? "モデル未選択"
  }
  let beepDetector = BeepDetector()
  let featureExtractionQueue = DispatchQueue(
    label: "dev.tuist.recording-test04.feature-extraction",
    qos: .userInitiated
  )

  var isRecording = false
  private var isAudioConfigurationLocked = false
  private var hasInstalledAudioTap = false
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
  var sessionLocationService: LocationService?
  var speedcsvTimer: Timer?
  var speedcsvData: [String] = []
  var eventcsvData: [String] = []
  var currentBaseFileName: String = ""
  var currentRecordingDirectory: URL?
  var currentOrientation: String = "横"
  var currentMicSource: String = "背面"
  var lastPredictionSuccessTime: TimeInterval?
  let preRollSamples: Int = 22050
  var preRollL: [Float] = []
  var preRollR: [Float] = []
  var localizationState: LocalizationState = .listeningForBeep
  var nextEventID: Int = 1
  var resultClearTask: Task<Void, Never>?
  private var routeInvalidationCancellable: AnyCancellable?
  var isWarningArmed = true
  let resultDisplaySeconds: TimeInterval = 3.0

  init(
    recordingFileStore: RecordingFileStoring,
    audioIOController: AudioIOController,
    modelSelection: DirectionModelSelectionController,
    clock: MeasurementClock,
    environment: MeasurementEnvironment
  ) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
    self.modelSelection = modelSelection
    self.clock = clock
    self.environment = environment
    routeInvalidationCancellable = NotificationCenter.default.publisher(
      for: .audioIORouteBecameInvalid
    )
    .sink { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.audioRouteBecameInvalid()
      }
    }
  }

  @MainActor
  func startDetecting(
    locationManager: LocationService,
    orientation: String,
    micSource: String,
    directionTag: MeasurementDirectionTag
  ) {
    guard !isRecording, modelSelection.beginMeasurement(),
      let predictor = modelSelection.predictor, let modelName = modelSelection.selectedModelName
    else {
      modelErrorMessage = "推論モデルが利用できません。Settingsで確認してください。"
      return
    }
    modelErrorMessage = nil
    sessionLocationService = locationManager
    sessionPredictor = predictor
    sessionModelName = modelName
    self.currentOrientation = orientation
    self.currentMicSource = micSource
    self.currentDirectionTag = directionTag.rawValue
    self.currentGroundTruth = directionTag == .none ? "FalseDetect" : directionTag.rawValue
    do {
      // WAVと2種類のCSVが同じSceneへ保存されるよう、開始時のURLを保持する。
      let recordingFile = try recordingFileStore.makeRecordingURL(prefix: "Detecting")
      self.currentBaseFileName = recordingFile.baseName
      self.currentRecordingDirectory = recordingFile.url.deletingLastPathComponent()
      let audioFilename = recordingFile.url

      _ = try audioIOController.configureForRecording(
        requiresStereo: true,
        allowsPlayback: true
      )

      let inputNode = audioEngine.inputNode
      let inputFormat = inputNode.inputFormat(forBus: 0)
      guard let audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
        AppLogger.audio.error("Audio Converterの作成に失敗しました")
        modelSelection.endMeasurement()
        return
      }

      audioFile = try AVAudioFile(forWriting: audioFilename, settings: targetFormat.settings)

      let sessionID = UUID()
      activeSessionID = sessionID
      featureExtractor = AudioFeatureExtractor()
      beepDetector.reset()
      resetPreRollBuffer()
      setLocalizationState(.listeningForBeep)
      resetDebugMetrics()
      resultClearTask?.cancel()
      resultClearTask = nil
      currentAIAngle = nil
      currentAIProbability = 0
      currentDirectionProbabilities = Array(repeating: 0, count: 8)
      activeEvent = nil
      nextEventID = 1
      isWarningArmed = true
      speedcsvData = [DetectionCSVHeader.measurement]
      eventcsvData = [DetectionCSVHeader.localization]
      let recordingAudioFile = audioFile
      let recordingFormat = targetFormat
      inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
        [weak self] buffer, _ in
        guard
          let convertedBuffer = Self.convertBuffer(
            buffer, converter: audioConverter, targetFormat: recordingFormat
          )
        else { return }
        do {
          try recordingAudioFile?.write(from: convertedBuffer)
        } catch {
          AppLogger.storage.error("検知音声の書き込みに失敗しました: \(error.localizedDescription)")
        }
        let bufferTime = Date()
        Task { @MainActor [weak self] in
          guard let self, self.activeSessionID == sessionID, self.isRecording else { return }
          self.calculateDecibel(buffer: convertedBuffer)
          self.handleLocalizationAudio(buffer: convertedBuffer, at: bufferTime)
        }
      }
      hasInstalledAudioTap = true
      audioEngine.prepare()
      sessionOrigin = clock.now()
      try audioEngine.start()
      lockAudioConfiguration()
      isRecording = true
      state = .safe
      elapsedTime = 0

      timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
        // These timers are registered on the main run loop by this MainActor method.
        MainActor.assumeIsolated {
          guard let self, self.activeSessionID == sessionID else { return }
          self.elapsedTime = self.clock.now() - self.sessionOrigin
        }
      }
      speedcsvTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.activeSessionID == sessionID,
            let locationService = self.sessionLocationService
          else { return }
          self.recordCSVLog(locationManager: locationService)
        }
      }

    } catch {
      activeSessionID = nil
      sessionPredictor = nil
      sessionLocationService = nil
      if hasInstalledAudioTap {
        audioEngine.inputNode.removeTap(onBus: 0)
        hasInstalledAudioTap = false
      }
      audioFile = nil
      modelSelection.endMeasurement()
      AppLogger.audio.error("検知録音の開始に失敗しました: \(error.localizedDescription)")
    }
  }

  @MainActor
  func stopDetecting() {
    guard isRecording else { return }
    if var event = activeEvent {
      event.cancelledAt = clock.now()
      event.outcome = "cancelled"
      event.failureKind = "measurement_stopped"
      appendLocalizationEvent(event)
    }
    activeEvent = nil
    activeSessionID = nil
    sessionPredictor = nil
    sessionLocationService = nil
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    hasInstalledAudioTap = false
    audioFile = nil
    isRecording = false
    modelSelection.endMeasurement()
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
    saveEventCSV()
    beepDetector.reset()
    resetPreRollBuffer()
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

  @MainActor
  private func audioRouteBecameInvalid() {
    guard isRecording else { return }
    stopDetecting()
    state = .unavailable
  }

}
