import Foundation

extension DetectionController {
  func appendLocalizationEvent(_ event: LocalizationEvent) {
    let prediction = event.prediction
    let probabilities =
      prediction?.probabilities.map { CSVCodec.decimal(Double($0), precision: 6) }
      ?? Array(repeating: "", count: 8)
    let completedTime =
      event.timing.predictionCompleted.map { CSVCodec.decimal($0 - event.origin) } ?? ""
    let updatedTime =
      (event.timing.uiUpdated ?? event.cancelledAt).map {
        CSVCodec.decimal($0 - event.origin)
      } ?? ""
    let fields =
      [
        String(event.eventID), event.modelName, updatedTime, event.groundTruth, event.directionTag,
        prediction.map { String($0.angle) } ?? "",
        prediction.map { CSVCodec.decimal(Double($0.maxProbability), precision: 6) } ?? "",
        (prediction.map { $0.maxProbability >= modelSelection.detectionThreshold } ?? false)
          .description,
      ] + probabilities + [
        CSVCodec.decimal(event.timing.beepDetected - event.origin), completedTime,
        event.timing.beepToPredictionMilliseconds.map { CSVCodec.decimal($0) } ?? "",
        event.warningTriggered.description,
        (prediction != nil).description,
      ] + event.timing.durationFields + event.timing.boundaryFields(relativeTo: event.origin) + [
        environment.deviceModel, environment.osVersion, environment.appVersion,
        environment.buildNumber,
        CSVCodec.decimal(Double(modelSelection.detectionThreshold)), "3", event.outcome,
        event.failureKind,
      ]
    eventcsvData.append(CSVCodec.row(fields))
  }

  func recordCSVLog(locationManager: LocationService) {
    let fields = [
      CSVCodec.decimal(clock.now() - sessionOrigin),
      CSVCodec.decimal(locationManager.speed * 3.6, precision: 1),
      CSVCodec.decimal(Double(currentDecibel), precision: 1), state.title,
      currentAIAngle.map(String.init) ?? "",
      currentAIAngle == nil ? "" : CSVCodec.decimal(Double(currentAIProbability), precision: 1),
      currentGroundTruth, currentDirectionTag, currentOrientation, currentMicSource,
      CSVCodec.decimal(debugLastUpdateMs), String(debugFeatureSkipCount),
      String(debugPredictionSkipCount),
      String(debugBeepDetectedCount), debugBeepDetectedThisFrame.description,
      CSVCodec.decimal(debugLastBeepElapsedTime),
      debugBeepToPredictionMs.map { CSVCodec.decimal($0) } ?? "",
      debugLocalizationState, String(debugBufferCount), debugFeatureCreated.description,
      debugPredictExecuted.description, debugPredictSuccess.description, debugMessage,
    ]
    speedcsvData.append(CSVCodec.row(fields))
    debugBeepDetectedThisFrame = false
  }

  func savespeedCSV() {
    saveCSVRows(speedcsvData, prefix: "")
  }

  func saveEventCSV() {
    saveCSVRows(eventcsvData, prefix: "Localization_")
  }

  private func saveCSVRows(_ rows: [String], prefix: String) {
    guard let currentRecordingDirectory else { return }
    let url = currentRecordingDirectory.appendingPathComponent(
      "\(prefix)\(currentBaseFileName).csv")
    do {
      try recordingFileStore.writeCSV(rows.joined(separator: "\n"), to: url)
    } catch {
      AppLogger.storage.error("計測CSVの保存に失敗しました: \(error.localizedDescription)")
    }
  }
}
