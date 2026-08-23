import Foundation

extension DetectionController {
  func appendLocalizationEvent(
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
        currentDirectionTag,
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

  func recordCSVLog(locationManager: LocationService) {

    let speed = locationManager.speed * 3.6
    let angle = currentAIAngle.map(String.init) ?? ""
    let probability =
      currentAIAngle == nil
      ? ""
      : String(format: "%.1f", currentAIProbability)

    let logLine = String(
      format: "%.2f,%.1f,%.1f,%@,%@,%@,%@,%@,%@,%@,%d,%@,%@,%@",
      elapsedTime,
      speed,
      currentDecibel,
      state.title,
      angle,
      probability,
      currentGroundTruth,
      currentDirectionTag,
      currentOrientation,
      currentMicSource,
      debugBufferCount,
      debugFeatureCreated.description,
      debugPredictExecuted.description,
      debugPredictSuccess.description
    )

    speedcsvData.append(logLine)
  }

  func recordDevCSVLog(locationManager: LocationService) {
    let speed = locationManager.speed * 3.6
    let angle = currentAIAngle.map(String.init) ?? ""
    let probability =
      currentAIAngle == nil
      ? ""
      : String(format: "%.1f", currentAIProbability)

    let logLine = String(
      format: "%.2f,%.1f,%.1f,%@,%@,%@,%@,%@,%@,%@,%.1f,%d,%d,%d,%@,%.2f,%.1f,%@,%d,%@,%@,%@,%@",
      elapsedTime,
      speed,
      currentDecibel,
      state.title,
      angle,
      probability,
      currentGroundTruth,
      currentDirectionTag,
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

  func savespeedCSV() {
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

  func saveDevCSV() {
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

  func saveEventCSV() {
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

  func csvEscaped(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
  }
}
