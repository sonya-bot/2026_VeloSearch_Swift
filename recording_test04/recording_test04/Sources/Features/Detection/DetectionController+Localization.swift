import AVFoundation
import CoreML
import Foundation

extension DetectionController {
  func handleLocalizationAudio(buffer: AVAudioPCMBuffer, at time: Date) {
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

  func setLocalizationState(_ state: LocalizationState) {
    localizationState = state
    debugLocalizationState = state.rawValue
  }

  func requestFeatureExtraction() {
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

  func startFeatureExtractionIfIdle() -> Bool {
    featureExtractionLock.lock()
    defer { featureExtractionLock.unlock() }

    if isExtractingFeatures {
      return false
    }

    isExtractingFeatures = true
    return true
  }

  func finishFeatureExtraction() {
    featureExtractionLock.lock()
    isExtractingFeatures = false
    featureExtractionLock.unlock()
  }

  func appendPreRoll(buffer: AVAudioPCMBuffer) {
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

  func currentPreRollSamples() -> (left: [Float], right: [Float]) {
    let count = min(preRollL.count, preRollR.count)
    guard count > 0 else { return ([], []) }

    return (
      Array(preRollL.suffix(count)),
      Array(preRollR.suffix(count))
    )
  }

  func resetPreRollBuffer() {
    preRollL.removeAll(keepingCapacity: true)
    preRollR.removeAll(keepingCapacity: true)
  }

  func executeAI(features: MLMultiArray) {
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

  func startPredictionIfIdle() -> Bool {
    predictionLock.lock()
    defer { predictionLock.unlock() }

    if isPredicting {
      return false
    }

    isPredicting = true
    return true
  }

  func finishPrediction() {
    predictionLock.lock()
    isPredicting = false
    predictionLock.unlock()
  }

  func scheduleResultClear() {
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

  func resetDebugMetrics() {
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

  func resetDetectionDisplay() {
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

}
