import AVFoundation
import CoreML
import Foundation

extension DetectionController {
  func handleLocalizationAudio(buffer: AVAudioPCMBuffer, at time: Date) {
    appendPreRoll(buffer: buffer)
    switch localizationState {
    case .listeningForBeep:
      guard beepDetector.detect(buffer: buffer, at: time), let sessionID = activeSessionID else {
        return
      }
      let detectedTime = clock.now()
      featureExtractor.reset()
      activeEvent = LocalizationEvent(
        sessionID: sessionID, eventID: nextEventID, modelName: sessionModelName,
        groundTruth: currentGroundTruth, directionTag: currentDirectionTag, origin: sessionOrigin,
        timing: LocalizationTiming(beepDetected: detectedTime)
      )
      nextEventID += 1
      debugBeepDetectedCount += 1
      debugBeepDetectedThisFrame = true
      debugLastBeepElapsedTime = detectedTime - sessionOrigin
      debugMessage = "Collecting localization audio"
      setLocalizationState(.collectingAudio)
      let preRoll = currentPreRollSamples()
      featureExtractor.append(samplesL: preRoll.left, samplesR: preRoll.right)
      requestFeatureExtraction()
    case .collectingAudio:
      featureExtractor.append(buffer: buffer)
      requestFeatureExtraction()
    case .predicting:
      break
    }
  }

  func setLocalizationState(_ state: LocalizationState) {
    localizationState = state
    debugLocalizationState = state.rawValue
  }

  func requestFeatureExtraction() {
    debugBufferCount = featureExtractor.currentBufferCount
    guard featureExtractor.isReady, var event = activeEvent, let predictor = sessionPredictor else {
      return
    }
    event.timing.audioReady = clock.now()
    activeEvent = event
    setLocalizationState(.predicting)
    let extractor = featureExtractor
    let measurementClock = clock
    // Each work item owns its event and extractor; a new recording never reuses them.
    featureExtractionQueue.async { [weak self] in
      var completedEvent = event
      completedEvent.timing.featureStarted = measurementClock.now()
      let features = extractor.extractIfReady()
      completedEvent.timing.featureCompleted = measurementClock.now()
      if let features {
        let inference = predictor.infer(features: features, clock: measurementClock)
        completedEvent.prediction = inference.prediction
        completedEvent.timing.predictionStarted = inference.started
        completedEvent.timing.predictionCompleted = inference.completed
        if inference.prediction == nil {
          completedEvent.outcome = "failure"
          completedEvent.failureKind = inference.failureKind
        }
      } else {
        completedEvent.outcome = "failure"
        completedEvent.failureKind = "feature_extraction_failed"
      }
      let result = completedEvent
      Task { @MainActor [weak self] in
        self?.applyLocalizationResult(result)
      }
    }
  }

  func applyLocalizationResult(_ result: LocalizationEvent) {
    guard isRecording, activeSessionID == result.sessionID,
      activeEvent?.eventID == result.eventID
    else { return }
    var event = result
    debugFeatureCreated =
      event.timing.featureCompleted != nil && event.failureKind != "feature_extraction_failed"
    debugPredictExecuted = event.timing.predictionStarted != nil
    debugPredictSuccess = event.prediction != nil
    if let prediction = event.prediction {
      currentAIAngle = prediction.angle
      currentAIProbability = prediction.maxProbability * 100
      currentDirectionProbabilities = prediction.probabilities
      let isAccepted = prediction.maxProbability >= modelSelection.detectionThreshold
      state = isAccepted ? .detect : .uncertain
      if isAccepted && isWarningArmed {
        warningTriggerID += 1
        isWarningArmed = false
        event.warningTriggered = true
      } else if !isAccepted {
        isWarningArmed = true
      }
    } else {
      currentAIAngle = nil
      currentAIProbability = 0
      currentDirectionProbabilities = Array(repeating: 0, count: 8)
      state = .uncertain
      debugMessage = "Localization failed"
    }
    // Capture UI state completion before any CSV formatting or feature cleanup.
    let updatedTime = clock.now()
    event.timing.uiUpdated = updatedTime
    debugBeepToPredictionMs = event.timing.beepToPredictionMilliseconds
    if let previousTime = lastPredictionSuccessTime, event.prediction != nil {
      debugLastUpdateMs = (updatedTime - previousTime) * 1000
    }
    if event.prediction != nil { lastPredictionSuccessTime = updatedTime }
    activeEvent = nil
    setLocalizationState(.listeningForBeep)
    scheduleResultClear()
    appendLocalizationEvent(event)
    featureExtractor.reset()
  }

  func appendPreRoll(buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData else { return }
    let frameLength = Int(buffer.frameLength)
    preRollL.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frameLength))
    let rightChannel = buffer.format.channelCount > 1 ? channelData[1] : channelData[0]
    preRollR.append(contentsOf: UnsafeBufferPointer(start: rightChannel, count: frameLength))
    if preRollL.count > preRollSamples {
      let removeCount = preRollL.count - preRollSamples
      preRollL.removeFirst(removeCount)
      preRollR.removeFirst(min(removeCount, preRollR.count))
    }
  }

  func currentPreRollSamples() -> (left: [Float], right: [Float]) {
    let count = min(preRollL.count, preRollR.count)
    return (Array(preRollL.suffix(count)), Array(preRollR.suffix(count)))
  }

  func resetPreRollBuffer() {
    preRollL.removeAll(keepingCapacity: true)
    preRollR.removeAll(keepingCapacity: true)
  }

  func scheduleResultClear() {
    resultClearTask?.cancel()
    resultClearTask = Task { @MainActor [weak self] in
      let nanoseconds = UInt64((self?.resultDisplaySeconds ?? 3.0) * 1_000_000_000)
      do {
        try await Task.sleep(nanoseconds: nanoseconds)
      } catch is CancellationError {
        return
      } catch {
        AppLogger.detection.error("結果表示タイマーに失敗しました: \(error.localizedDescription)")
        return
      }
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
    debugBeepToPredictionMs = nil
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
