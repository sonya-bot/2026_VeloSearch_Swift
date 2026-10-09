import Foundation

struct LocalizationTiming {
  var beepDetected: TimeInterval
  var audioReady: TimeInterval?
  var featureStarted: TimeInterval?
  var featureCompleted: TimeInterval?
  var predictionStarted: TimeInterval?
  var predictionCompleted: TimeInterval?
  var uiUpdated: TimeInterval?

  var beepToPredictionMilliseconds: Double? {
    predictionCompleted.map { max(0, $0 - beepDetected) * 1000 }
  }

  private func milliseconds(from start: TimeInterval?, to end: TimeInterval?) -> String {
    guard let start, let end else { return "" }
    return CSVCodec.decimal(max(0, end - start) * 1000)
  }

  var durationFields: [String] {
    [
      milliseconds(from: beepDetected, to: audioReady),
      milliseconds(from: featureStarted, to: featureCompleted),
      milliseconds(from: predictionStarted, to: predictionCompleted),
      milliseconds(from: predictionCompleted, to: uiUpdated),
      milliseconds(from: beepDetected, to: uiUpdated),
    ]
  }

  func boundaryFields(relativeTo origin: TimeInterval) -> [String] {
    [
      audioReady, featureStarted, featureCompleted, predictionStarted, predictionCompleted,
      uiUpdated,
    ]
    .map { value in value.map { CSVCodec.decimal($0 - origin) } ?? "" }
  }
}

struct LocalizationEvent {
  let sessionID: UUID
  let eventID: Int
  let modelName: String
  let groundTruth: String
  let directionTag: String
  let origin: TimeInterval
  var timing: LocalizationTiming
  var prediction: DirectionPrediction?
  var cancelledAt: TimeInterval?
  var failureKind = ""
  var outcome = "success"
  var warningTriggered = false
}
