import AVFoundation
import AudioToolbox
import CoreML
import Foundation
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct DetectionView_Previews: PreviewProvider {
  static var previews: some View {
    DetectionView(recordingFileStore: RecordingFileStore.shared)
  }
}

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

private enum DetectionCSVHeader {
  static let measurement = [
    "elapsed_time", "speed_kmh", "volume_db", "status", "ai_angle",
    "ai_probability", "ground_truth_angle", "device_orientation", "mic_source",
    "buffer_count", "feature_created", "predict_executed", "predict_success",
  ].joined(separator: ",")

  static let development = [
    "elapsed_time", "speed_kmh", "volume_db", "status", "ai_angle",
    "ai_probability", "ground_truth_angle", "device_orientation", "mic_source",
    "update_ms", "feature_skip_count", "prediction_skip_count", "beep_detected_count",
    "beep_detected_this_frame", "last_beep_elapsed_time", "beep_to_prediction_ms",
    "localization_state", "buffer_count", "feature_created", "predict_executed",
    "predict_success", "debug_message",
  ].joined(separator: ",")

  static let localization = [
    "event_id", "model_name", "elapsed_time", "ground_truth_angle", "predicted_angle",
    "max_probability", "accepted", "prob_000", "prob_045", "prob_090", "prob_135",
    "prob_180", "prob_225", "prob_270", "prob_315", "beep_detected_time",
    "prediction_completed_time", "beep_to_prediction_ms", "warning_triggered",
    "prediction_success",
  ].joined(separator: ",")
}

// MARK: - 1. Detecting (検知ロジック)
@Observable
final class DetectionController {
  private let recordingFileStore: RecordingFileStoring
  private let audioEngine = AVAudioEngine()
  private var audioFile: AVAudioFile?
  private var beepPlayer: AVAudioPlayer?
  private var beepPlaybackTask: Task<Void, Never>?
  // Core MLの特徴量抽出は44.1kHz / stereo / Float32を前提にしている。
  private let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 44100,
    channels: 2,
    interleaved: false
  )!

  private let featureExtractor = AudioFeatureExtractor()
  private let mlManager = DirectionModelService()
  private let beepDetector = BeepDetector()
  private let featureExtractionQueue = DispatchQueue(
    label: "dev.tuist.recording-test04.feature-extraction",
    qos: .userInitiated
  )

  var isRecording = false
  var isBeepPlaying = false
  var state: DetectionState = .standby
  var elapsedTime: TimeInterval = 0.0
  var currentDecibel: Float = -160.0

  var currentAIAngle: Int?
  var currentAIProbability: Float = 0.0
  var currentDirectionProbabilities: [Float] = Array(repeating: 0.0, count: 8)
  var currentGroundTruth: String = "FalseDetect"  // ピッカー選択値
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

  private var timer: Timer?
  private var startTime: Date?
  private var speedcsvTimer: Timer?
  private var speedcsvData: [String] = []
  private var devcsvData: [String] = []
  private var eventcsvData: [String] = []
  private var currentBaseFileName: String = ""
  private var currentRecordingDirectory: URL?
  private var currentOrientation: String = "横"
  private var currentMicSource: String = "背面"
  private let featureExtractionLock = NSLock()
  private var isExtractingFeatures = false
  private let predictionLock = NSLock()
  private var isPredicting = false
  private var lastPredictionSuccessTime: Date?
  // ビープ音そのものを定位対象にするため、検知後の待機は入れない。
  private let localizationDelaySeconds: TimeInterval = 0.0
  private let preRollSamples: Int = 22050
  private var preRollL: [Float] = []
  private var preRollR: [Float] = []
  private var localizationState: LocalizationState = .listeningForBeep
  private var beepDetectedAt: Date?
  private var pendingEventID: Int?
  private var pendingGroundTruth: String = "FalseDetect"
  private var nextEventID: Int = 1
  private var resultClearTask: Task<Void, Never>?
  private var isWarningArmed = true
  private let resultDisplaySeconds: TimeInterval = 3.0

  init(recordingFileStore: RecordingFileStoring) {
    self.recordingFileStore = recordingFileStore
  }

  func playBeepSound() {
    guard isRecording else {
      AppLogger.detection.notice("Detect録音中のみBeep Testを再生できます")
      return
    }

    guard let soundURL = Bundle.main.url(forResource: "beep", withExtension: "wav") else {
      AppLogger.audio.error("beep.wavが見つかりません")
      return
    }

    do {
      let audioSession = AVAudioSession.sharedInstance()
      // Beep TestもMonitoring画面と同じ再生ルートを明示し、端末スピーカーから出力する。
      try audioSession.setCategory(
        .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
      try audioSession.setActive(true)
      try configureInputSession(
        audioSession, orientation: currentOrientation, micSource: currentMicSource)

      beepPlayer = try AVAudioPlayer(contentsOf: soundURL)
      beepPlayer?.prepareToPlay()
      beepPlayer?.play()
      isBeepPlaying = true

      let duration = beepPlayer?.duration ?? 0.0
      beepPlaybackTask?.cancel()
      beepPlaybackTask = Task { @MainActor [weak self] in
        let nanoseconds = UInt64(max(duration, 0.0) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
        guard !Task.isCancelled else { return }
        self?.isBeepPlaying = false
      }
    } catch {
      isBeepPlaying = false
      AppLogger.audio.error("beep.wavの再生に失敗しました: \(error.localizedDescription)")
    }
  }

  func startDetecting(locationManager: LocationService, orientation: String, micSource: String) {
    self.currentOrientation = orientation
    self.currentMicSource = micSource
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

  private func configureInputSession(
    _ audioSession: AVAudioSession,
    orientation: String,
    micSource: String
  ) throws {
    // Monitoring画面と同じ条件で録音するため、
    // 内蔵マイクの面とステレオ指向性を明示する。
    if let availableInputs = audioSession.availableInputs,
      let builtInMic = availableInputs.first(where: { $0.portType == .builtInMic }),
      let dataSources = builtInMic.dataSources
    {
      let targetOrientation: AVAudioSession.Orientation = (micSource == "背面") ? .back : .front

      if let selectedDataSource = dataSources.first(where: { $0.orientation == targetOrientation })
      {
        try builtInMic.setPreferredDataSource(selectedDataSource)

        if let supportedPatterns = selectedDataSource.supportedPolarPatterns,
          supportedPatterns.contains(.stereo)
        {
          try selectedDataSource.setPreferredPolarPattern(.stereo)
        } else {
          AppLogger.audio.notice("選択したマイクはステレオ入力に対応していません")
        }

        try audioSession.setPreferredInput(builtInMic)
      }
    }

    // 端末向きはマイク選択後に反映する。順序はMonitoring画面と揃える。
    if orientation == "縦" {
      try audioSession.setPreferredInputOrientation(.portrait)
    } else {
      try audioSession.setPreferredInputOrientation(.landscapeRight)
    }
  }

  private func convertBuffer(
    _ buffer: AVAudioPCMBuffer,
    converter: AVAudioConverter,
    targetFormat: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let inputSampleRate = buffer.format.sampleRate
    guard inputSampleRate > 0 else { return nil }

    let sampleRateRatio = targetFormat.sampleRate / inputSampleRate
    let outputCapacity =
      AVAudioFrameCount(ceil(Double(buffer.frameLength) * sampleRateRatio)) + 1024
    guard
      let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity)
    else {
      return nil
    }

    var didProvideInput = false
    var conversionError: NSError?

    // 1つのtap bufferにつき入力は一度だけ供給する。返し続けると変換が不正になる。
    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
      if didProvideInput {
        outStatus.pointee = .noDataNow
        return nil
      }

      didProvideInput = true
      outStatus.pointee = .haveData
      return buffer
    }

    if status == .error {
      if let conversionError {
        AppLogger.audio.error(
          "音声形式の変換に失敗しました: \(conversionError.localizedDescription)"
        )
      }
      return nil
    }

    return outputBuffer.frameLength > 0 ? outputBuffer : nil
  }

  private func handleLocalizationAudio(buffer: AVAudioPCMBuffer, at time: Date) {
    appendPreRoll(buffer: buffer)

    switch localizationState {
    case .listeningForBeep:
      guard beepDetector.detect(buffer: buffer, at: time) else { return }

      featureExtractor.reset()
      beepDetectedAt = time
      pendingEventID = nextEventID
      nextEventID += 1
      pendingGroundTruth = currentGroundTruth
      debugBeepDetectedCount += 1
      debugBeepDetectedThisFrame = true
      debugLastBeepElapsedTime = elapsedTime
      debugMessage = "Beep detected"
      setLocalizationState(.waitingAfterBeep)

      if localizationDelaySeconds <= 0 {
        debugMessage = "Collecting localization audio"
        setLocalizationState(.collectingAudio)
        let preRoll = currentPreRollSamples()
        featureExtractor.append(samplesL: preRoll.left, samplesR: preRoll.right)
        requestFeatureExtraction()
      }

    case .waitingAfterBeep:
      guard let beepDetectedAt else {
        setLocalizationState(.listeningForBeep)
        return
      }

      guard time.timeIntervalSince(beepDetectedAt) >= localizationDelaySeconds else { return }

      featureExtractor.reset()
      debugMessage = "Collecting localization audio"
      setLocalizationState(.collectingAudio)
      featureExtractor.append(buffer: buffer)
      requestFeatureExtraction()

    case .collectingAudio:
      featureExtractor.append(buffer: buffer)
      requestFeatureExtraction()

    case .predicting:
      return
    }
  }

  private func setLocalizationState(_ state: LocalizationState) {
    localizationState = state
    debugLocalizationState = state.rawValue
  }

  private func requestFeatureExtraction() {
    guard startFeatureExtractionIfIdle() else {
      DispatchQueue.main.async {
        self.debugFeatureSkipCount += 1
        self.debugMessage = "Feature extraction skipped: previous extraction is still running"
      }
      return
    }

    featureExtractionQueue.async { [weak self] in
      guard let self = self else { return }
      defer {
        self.finishFeatureExtraction()
      }

      let features = self.featureExtractor.extractIfReady()
      let currentBufferCount = self.featureExtractor.currentBufferCount

      DispatchQueue.main.async {
        self.debugBufferCount = currentBufferCount
        self.debugFeatureCreated = features != nil
      }

      guard let features else { return }
      self.setLocalizationState(.predicting)
      self.executeAI(features: features)
    }
  }

  private func startFeatureExtractionIfIdle() -> Bool {
    featureExtractionLock.lock()
    defer { featureExtractionLock.unlock() }

    if isExtractingFeatures {
      return false
    }

    isExtractingFeatures = true
    return true
  }

  private func finishFeatureExtraction() {
    featureExtractionLock.lock()
    isExtractingFeatures = false
    featureExtractionLock.unlock()
  }

  func stopDetecting() {
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    audioFile = nil
    isRecording = false
    state = .standby

    timer?.invalidate()
    speedcsvTimer?.invalidate()
    resultClearTask?.cancel()
    resultClearTask = nil
    // Sceneが例外的に消失していた場合は、CSVだけでもDefaultへ退避する。
    if let directory = currentRecordingDirectory,
      !FileManager.default.fileExists(atPath: directory.path)
    {
      try? recordingFileStore.prepareStorage()
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

  private func appendPreRoll(buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData else { return }

    let frameLength = Int(buffer.frameLength)
    let ptrL = channelData[0]
    let ptrR = buffer.format.channelCount > 1 ? channelData[1] : channelData[0]

    preRollL.append(contentsOf: UnsafeBufferPointer(start: ptrL, count: frameLength))
    preRollR.append(contentsOf: UnsafeBufferPointer(start: ptrR, count: frameLength))

    if preRollL.count > preRollSamples {
      let removeCount = preRollL.count - preRollSamples
      preRollL.removeFirst(removeCount)
      preRollR.removeFirst(min(removeCount, preRollR.count))
    }
  }

  private func currentPreRollSamples() -> (left: [Float], right: [Float]) {
    let count = min(preRollL.count, preRollR.count)
    guard count > 0 else { return ([], []) }

    return (
      Array(preRollL.suffix(count)),
      Array(preRollR.suffix(count))
    )
  }

  private func resetPreRollBuffer() {
    preRollL.removeAll(keepingCapacity: true)
    preRollR.removeAll(keepingCapacity: true)
  }

  private func executeAI(features: MLMultiArray) {
    guard startPredictionIfIdle() else {
      Task { @MainActor in
        self.debugPredictionSkipCount += 1
        self.debugPredictExecuted = false
        self.debugMessage = "Prediction skipped: previous inference is still running"
      }
      return
    }

    Task { @MainActor in
      self.debugPredictExecuted = true
    }
    Task.detached { [weak self] in
      guard let self = self else { return }
      defer {
        self.finishPrediction()
      }

      if let result = self.mlManager.predict(features: features) {
        Task { @MainActor in
          guard self.isRecording else { return }

          let now = Date()
          let predictionCompletedTime = self.elapsedTime
          let beepDetectedTime = self.debugLastBeepElapsedTime
          if let lastPredictionSuccessTime = self.lastPredictionSuccessTime {
            self.debugLastUpdateMs = now.timeIntervalSince(lastPredictionSuccessTime) * 1000.0
          }
          self.lastPredictionSuccessTime = now
          self.debugPredictSuccess = true
          if let beepDetectedAt = self.beepDetectedAt {
            self.debugBeepToPredictionMs = now.timeIntervalSince(beepDetectedAt) * 1000.0
          }

          self.currentAIAngle = result.angle
          self.currentAIProbability = result.maxProbability * 100.0
          self.currentDirectionProbabilities = result.probabilities

          let accepted = result.maxProbability >= self.mlManager.detectionThreshold
          var warningTriggered = false
          if accepted {
            self.state = .detect
            if self.isWarningArmed {
              self.warningTriggerID += 1
              self.isWarningArmed = false
              warningTriggered = true
            }
          } else {
            self.state = .uncertain
            self.isWarningArmed = true
          }

          self.appendLocalizationEvent(
            eventID: self.pendingEventID,
            groundTruth: self.pendingGroundTruth,
            predictedAngle: result.angle,
            maxProbability: result.maxProbability,
            probabilities: result.probabilities,
            accepted: accepted,
            beepDetectedTime: beepDetectedTime,
            predictionCompletedTime: predictionCompletedTime,
            beepToPredictionMs: self.debugBeepToPredictionMs,
            warningTriggered: warningTriggered,
            predictionSuccess: true
          )
          self.scheduleResultClear()
          self.featureExtractor.reset()
          self.beepDetectedAt = nil
          self.pendingEventID = nil
          self.setLocalizationState(.listeningForBeep)
        }
      } else {
        Task { @MainActor in
          guard self.isRecording else { return }
          self.debugPredictSuccess = false
          self.appendLocalizationEvent(
            eventID: self.pendingEventID,
            groundTruth: self.pendingGroundTruth,
            predictedAngle: nil,
            maxProbability: nil,
            probabilities: nil,
            accepted: false,
            beepDetectedTime: self.debugLastBeepElapsedTime,
            predictionCompletedTime: self.elapsedTime,
            beepToPredictionMs: self.beepDetectedAt.map {
              Date().timeIntervalSince($0) * 1000.0
            } ?? 0.0,
            warningTriggered: false,
            predictionSuccess: false
          )
          self.featureExtractor.reset()
          self.beepDetectedAt = nil
          self.pendingEventID = nil
          self.setLocalizationState(.listeningForBeep)
        }
      }
    }
  }

  private func startPredictionIfIdle() -> Bool {
    predictionLock.lock()
    defer { predictionLock.unlock() }

    if isPredicting {
      return false
    }

    isPredicting = true
    return true
  }

  private func finishPrediction() {
    predictionLock.lock()
    isPredicting = false
    predictionLock.unlock()
  }

  private func scheduleResultClear() {
    resultClearTask?.cancel()
    resultClearTask = Task { @MainActor [weak self] in
      let nanoseconds = UInt64((self?.resultDisplaySeconds ?? 3.0) * 1_000_000_000)
      try? await Task.sleep(nanoseconds: nanoseconds)
      guard !Task.isCancelled, let self else { return }

      self.currentAIAngle = nil
      self.currentAIProbability = 0.0
      self.currentDirectionProbabilities = Array(repeating: 0.0, count: 8)
      self.state = self.isRecording ? .safe : .standby
      self.isWarningArmed = true
      self.resultClearTask = nil
    }
  }

  private func resetDebugMetrics() {
    debugBufferCount = 0
    debugFeatureCreated = false
    debugPredictExecuted = false
    debugPredictSuccess = false
    debugMessage = ""
    debugLastUpdateMs = 0.0
    debugFeatureSkipCount = 0
    debugPredictionSkipCount = 0
    debugBeepDetectedCount = 0
    debugBeepDetectedThisFrame = false
    debugLocalizationState = LocalizationState.listeningForBeep.rawValue
    debugLastBeepElapsedTime = 0.0
    debugBeepToPredictionMs = 0.0
    lastPredictionSuccessTime = nil
  }

  private func resetDetectionDisplay() {
    resultClearTask?.cancel()
    resultClearTask = nil
    elapsedTime = 0.0
    currentDecibel = -160.0
    currentAIAngle = nil
    currentAIProbability = 0.0
    currentDirectionProbabilities = Array(repeating: 0.0, count: 8)
    currentGroundTruth = "FalseDetect"
    isWarningArmed = true
    resetDebugMetrics()
  }

  private func calculateDecibel(buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData?[0] else { return }
    let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map
    { channelData[$0] }
    let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
    let avgPower = 20 * log10(rms)
    DispatchQueue.main.async {
      self.currentDecibel = avgPower.isNaN || avgPower.isInfinite ? -160.0 : max(avgPower, -160.0)
    }
  }

  private func appendLocalizationEvent(
    eventID: Int?,
    groundTruth: String,
    predictedAngle: Int?,
    maxProbability: Float?,
    probabilities: [Float]?,
    accepted: Bool,
    beepDetectedTime: TimeInterval,
    predictionCompletedTime: TimeInterval,
    beepToPredictionMs: TimeInterval,
    warningTriggered: Bool,
    predictionSuccess: Bool
  ) {
    let probabilityFields: [String]
    if let probabilities, probabilities.count == 8 {
      probabilityFields = probabilities.map { String(format: "%.6f", $0) }
    } else {
      probabilityFields = Array(repeating: "", count: 8)
    }

    let fields =
      [
        eventID.map(String.init) ?? "",
        DirectionModelService.modelName,
        String(format: "%.2f", predictionCompletedTime),
        groundTruth,
        predictedAngle.map(String.init) ?? "",
        maxProbability.map { String(format: "%.6f", $0) } ?? "",
        accepted.description,
      ] + probabilityFields + [
        String(format: "%.2f", beepDetectedTime),
        String(format: "%.2f", predictionCompletedTime),
        String(format: "%.1f", beepToPredictionMs),
        warningTriggered.description,
        predictionSuccess.description,
      ]

    eventcsvData.append(fields.map(csvEscaped).joined(separator: ","))
  }

  private func recordCSVLog(locationManager: LocationService) {

    let speed = locationManager.speed * 3.6
    let angle = currentAIAngle.map(String.init) ?? ""
    let probability =
      currentAIAngle == nil
      ? ""
      : String(format: "%.1f", currentAIProbability)

    let logLine = String(
      format: "%.2f,%.1f,%.1f,%@,%@,%@,%@,%@,%@,%d,%@,%@,%@",
      elapsedTime,
      speed,
      currentDecibel,
      state.title,
      angle,
      probability,
      currentGroundTruth,
      currentOrientation,
      currentMicSource,
      debugBufferCount,
      debugFeatureCreated.description,
      debugPredictExecuted.description,
      debugPredictSuccess.description
    )

    speedcsvData.append(logLine)
  }

  private func recordDevCSVLog(locationManager: LocationService) {
    let speed = locationManager.speed * 3.6
    let angle = currentAIAngle.map(String.init) ?? ""
    let probability =
      currentAIAngle == nil
      ? ""
      : String(format: "%.1f", currentAIProbability)

    let logLine = String(
      format: "%.2f,%.1f,%.1f,%@,%@,%@,%@,%@,%@,%.1f,%d,%d,%d,%@,%.2f,%.1f,%@,%d,%@,%@,%@,%@",
      elapsedTime,
      speed,
      currentDecibel,
      state.title,
      angle,
      probability,
      currentGroundTruth,
      currentOrientation,
      currentMicSource,
      debugLastUpdateMs,
      debugFeatureSkipCount,
      debugPredictionSkipCount,
      debugBeepDetectedCount,
      debugBeepDetectedThisFrame.description,
      debugLastBeepElapsedTime,
      debugBeepToPredictionMs,
      debugLocalizationState,
      debugBufferCount,
      debugFeatureCreated.description,
      debugPredictExecuted.description,
      debugPredictSuccess.description,
      csvEscaped(debugMessage)
    )

    devcsvData.append(logLine)
    // 0.1秒ごとのCSV行でビープ発生タイミングを1回だけ示す。
    debugBeepDetectedThisFrame = false
  }

  private func savespeedCSV() {
    guard let currentRecordingDirectory else { return }
    let path = currentRecordingDirectory.appendingPathComponent("\(currentBaseFileName).csv")
    do {
      try speedcsvData.joined(separator: "\n").write(
        to: path,
        atomically: true,
        encoding: .utf8
      )
    } catch {
      AppLogger.storage.error("計測CSVの保存に失敗しました: \(error.localizedDescription)")
    }
  }

  private func saveDevCSV() {
    guard let currentRecordingDirectory else { return }
    let path = currentRecordingDirectory.appendingPathComponent("Dev_\(currentBaseFileName).csv")
    do {
      try devcsvData.joined(separator: "\n").write(
        to: path,
        atomically: true,
        encoding: .utf8
      )
    } catch {
      AppLogger.storage.error("Dev CSVの保存に失敗しました: \(error.localizedDescription)")
    }
  }

  private func saveEventCSV() {
    guard let currentRecordingDirectory else { return }
    let path = currentRecordingDirectory.appendingPathComponent(
      "Localization_\(currentBaseFileName).csv")
    do {
      try eventcsvData.joined(separator: "\n").write(
        to: path,
        atomically: true,
        encoding: .utf8
      )
    } catch {
      AppLogger.storage.error("Localization CSVの保存に失敗しました: \(error.localizedDescription)")
    }
  }

  private func csvEscaped(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
  }
}

// MARK: -2 DetentingsView(画面UI)
struct DetectionView: View {
  @State private var detection: DetectionController
  @State private var locationManager = LocationService()
  @AppStorage("warningSoundID") private var selectedSoundID: Int = 1052
  @AppStorage("deviceOrientation") private var selectedOrientation: String = "横"
  @AppStorage("micSource") private var selectedMicSource: String = "背面"
  @AppStorage("showDebugOverlay") private var showDebugOverlay = false

  // 正解入力ピッカーの選択肢
  let truthOptions = ["FalseDetect", "0°", "45°", "90°", "135°", "180°", "225°", "270°", "315°"]

  init(recordingFileStore: RecordingFileStoring) {
    _detection = State(
      initialValue: DetectionController(recordingFileStore: recordingFileStore)
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color(UIColor.systemGroupedBackground).ignoresSafeArea()

        GeometryReader { geometry in
          let isLandscape = geometry.size.width > geometry.size.height

          if isLandscape {
            // 横画面レイアウト: 左右に2分割
            HStack(spacing: 0) {
              // 左半分 (ステータス + レーダー)
              VStack(spacing: 8) {
                Spacer(minLength: 0)
                statusView
                  .padding(.bottom, 10)
                radarSection(isLandscape: isLandscape)
                Spacer(minLength: 0)
              }
              .frame(width: (geometry.size.width - 30) / 3)

              // 右半分 (速度/音量 + ピッカー + ボタン)
              VStack(spacing: 8) {
                Spacer(minLength: 0)
                micAssignmentLabels
                  .padding(.top, -20)
                groundTruthPicker
                HStack(spacing: 16) {
                  controlButton
                  beepButton
                }
                Spacer(minLength: 0)
              }
              .frame(width: (geometry.size.width - 30) * 2 / 3)
            }
          } else {
            // 縦画面レイアウト (従来通り)
            VStack(spacing: 0) {
              statusView
              micAssignmentLabels
              Spacer(minLength: 0)
              radarSection(isLandscape: isLandscape)
              Spacer(minLength: 0)
              groundTruthPicker
                .padding(.bottom, 16)
              HStack(spacing: 0) {
                controlButton
                beepButton
              }
              .padding(.bottom, 16)
            }
          }
        }
      }
      .navigationTitle("Detection")
      .navigationBarTitleDisplayMode(.inline)
      // 連続したDetect期間につき、アラート音は最初の1回だけ再生する。
      .onChange(of: detection.warningTriggerID) { oldValue, newValue in
        if newValue > oldValue {
          AudioServicesPlaySystemSound(SystemSoundID(selectedSoundID))
        }
      }
    }
  }

  // MARK: - UI Components
  private var statusView: some View {
    let statusText: String
    if let angle = detection.currentAIAngle,
      detection.state == .detect || detection.state == .uncertain
    {
      statusText = "\(detection.state.title) (\(angle)°)"
    } else {
      statusText = detection.state.title
    }
    return Text(statusText)
      .font(.system(size: 28, weight: .bold))
      .minimumScaleFactor(0.5)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15)))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(detection.state.themeColor, lineWidth: 2))
      .padding(.horizontal, 24)
      .padding(.top, 10)
  }

  private func radarSection(isLandscape: Bool) -> some View {
    RadarView(state: detection.state, aiAngle: detection.currentAIAngle)
      .aspectRatio(1, contentMode: .fit)
      .frame(maxWidth: 220, maxHeight: 220)
      .overlay(alignment: .bottomTrailing) {
        if showDebugOverlay {
          debugOverlay(isLandscape: isLandscape)
        }
      }
  }

  private func debugOverlay(isLandscape: Bool) -> some View {
    let angleText = detection.currentAIAngle.map(String.init) ?? "--"
    let probabilityText =
      detection.currentAIAngle == nil
      ? "--"
      : String(Int(detection.currentAIProbability))
    return VStack(alignment: .leading, spacing: 4) {
      Text("AI: \(angleText)deg / \(probabilityText)%")
      Text("Update: \(Int(detection.debugLastUpdateMs))ms")
      Text(
        "Skipped: Extract \(detection.debugFeatureSkipCount) / AI \(detection.debugPredictionSkipCount)"
      )
    }
    .font(.system(size: 12, weight: .medium, design: .monospaced))
    .foregroundStyle(.primary)
    //        .padding(.horizontal, 6)
    //        .padding(.vertical, 5)
    .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemBackground).opacity(0.82)))
    .overlay(
      RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
    )
    .offset(x: isLandscape ? -50 : 80, y: 20)
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

          // 2. 真ん中: 端末の向き
          VStack(spacing: 6) {
            Image(systemName: selectedOrientation == "縦" ? "iphone" : "iphone.landscape")
              .font(.title2)
            Text(selectedOrientation == "縦" ? "Portrait" : "Landscape")
              .font(.caption)
          }
          .frame(maxWidth: .infinity)

          Divider()
            .overlay(Color.gray)

          // 3. 右側: 音量確認
          VStack(spacing: 6) {
            Text("Volume").font(.caption).foregroundStyle(.secondary)
            let decibelText =
              detection.currentDecibel <= -160.0
              ? "0.0" : String(format: "%.1f", detection.currentDecibel)
            Text("\(decibelText) dB").font(.title3).monospacedDigit()
          }
          .frame(maxWidth: .infinity)
        }
      }
    }
    .listStyle(.insetGrouped)
    .frame(height: 125)
    .scrollDisabled(true)
    .scrollContentBackground(.hidden)
  }

  private var groundTruthPicker: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Ground Truth (正解/誤検知ラベル)").font(.caption).foregroundStyle(.secondary).padding(
        .horizontal, 24)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(truthOptions, id: \.self) { option in
            Button(action: {
              detection.currentGroundTruth =
                option == "FalseDetect"
                ? "FalseDetect" : option.replacingOccurrences(of: "°", with: "")
            }) {
              Text(option == "FalseDetect" ? "誤検知" : option)
                .font(.subheadline).bold()
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(
                  detection.currentGroundTruth
                    == (option == "FalseDetect"
                      ? "FalseDetect" : option.replacingOccurrences(of: "°", with: ""))
                    ? Color.blue : Color.gray.opacity(0.2)
                )
                .foregroundColor(
                  detection.currentGroundTruth
                    == (option == "FalseDetect"
                      ? "FalseDetect" : option.replacingOccurrences(of: "°", with: ""))
                    ? .white : .primary
                )
                .cornerRadius(8)
            }
          }
        }
        .padding(.horizontal, 24)
      }
    }
  }

  @ViewBuilder
  private var controlButton: some View {
    Button(action: {
      withAnimation(.spring()) {
        if detection.isRecording {
          detection.stopDetecting()
        } else {
          detection.startDetecting(
            locationManager: locationManager, orientation: selectedOrientation,
            micSource: selectedMicSource)
        }
      }
    }) {
      Text(detection.isRecording ? "Stop" : "Start")
        .font(.title2).bold().foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(detection.isRecording ? .red : .blue)
        .clipShape(Capsule())
    }
    .padding(.horizontal, 24)
    .sensoryFeedback(.impact(flexibility: .solid), trigger: detection.isRecording)
  }

  private var beepButton: some View {
    Button(action: {
      detection.playBeepSound()
    }) {
      Text(detection.isBeepPlaying ? "Playing" : "Beep Test")
        .font(.title2).bold().foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Color.orange.opacity(beepButtonOpacity))
        .clipShape(Capsule())
    }
    .padding(.horizontal, 24)
    .disabled(!detection.isRecording || detection.isBeepPlaying)
  }

  private var beepButtonOpacity: Double {
    if !detection.isRecording { return 0.25 }
    if detection.isBeepPlaying { return 0.45 }
    return 1.0
  }
}

// 動的レーダーUI
struct RadarView: View {
  let state: DetectionState
  let aiAngle: Int?

  var body: some View {
    ZStack {
      Canvas { context, size in
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = size.width / 2
        for i in 1...3 {
          let radius = maxRadius * CGFloat(i) / 3
          context.stroke(
            Path(
              ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.secondary.opacity(0.2)), lineWidth: 1)
        }
        for i in 0..<8 {
          let angle = Angle.degrees(Double(i) * 45)
          var path = Path()
          path.move(to: center)
          path.addLine(
            to: CGPoint(
              x: center.x + maxRadius * cos(CGFloat(angle.radians)),
              y: center.y + maxRadius * sin(CGFloat(angle.radians))))
          context.stroke(path, with: .color(.secondary.opacity(0.1)), lineWidth: 1)
        }
      }

      if state == .detect, let aiAngle {
        SectorHighlight(state: state)
          // 真上が0度になるように -90度オフセットし、AIの角度を加算して回転
          .rotationEffect(.degrees(Double(aiAngle - 90)))
      }

      Circle()
        .fill(Color.gray)
        .frame(width: 40, height: 40)
        .symbolEffect(.pulse, isActive: state != .standby)
    }
  }
}

struct SectorHighlight: View {
  let state: DetectionState
  @State private var opacity = 0.8
  var body: some View {
    GeometryReader { geometry in
      Path { path in
        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let radius = geometry.size.width / 2
        path.move(to: center)
        // 45度の扇形（±22.5度）
        path.addArc(
          center: center, radius: radius, startAngle: .degrees(-22.5), endAngle: .degrees(22.5),
          clockwise: false)
        path.closeSubpath()
      }
      .fill(state.themeColor.opacity(opacity))
      .onAppear {
        withAnimation(.easeInOut(duration: 0.4).repeatForever()) { opacity = 0.3 }
      }
    }
  }
}
