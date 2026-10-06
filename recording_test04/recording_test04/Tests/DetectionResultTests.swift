import Foundation
import Testing

@testable import recording_test04

@MainActor
struct DetectionResultTests {
  @Test
  func resultUpdatesUIAndThenLogsExactTimings() throws {
    let controller = try makeController()
    let event = makeEvent()
    controller.isRecording = true
    controller.activeSessionID = event.sessionID
    controller.activeEvent = event
    controller.applyLocalizationResult(event)
    #expect(controller.state == .detect)
    #expect(controller.currentAIAngle == 45)
    #expect(controller.warningTriggerID == 1)
    let csvRow = try #require(controller.eventcsvData.first)
    let row = try #require(CSVCodec.parse(csvRow).first)
    let headers = try #require(CSVCodec.parse(DetectionCSVHeader.localization).first)
    #expect(row.count == headers.count)
    let values = Dictionary(uniqueKeysWithValues: zip(headers, row))
    #expect(values["model_name"] == "RC_CNN")
    #expect(values["inference_ms"] == "100.000")
    #expect(values["ui_update_ms"] == "25.000")
    #expect(values["total_ms"] == "2025.000")
    #expect(values["outcome"] == "success")
    controller.resultClearTask?.cancel()
  }

  @Test
  func displayedModelUsesSelectionAtRestAndSessionSnapshotDuringMeasurement() async throws {
    let controller = try makeController()
    #expect(controller.displayedModelName == "モデル未選択")
    let repository = MemoryModelSelectionRepository()
    let selection = DirectionModelSelectionController(
      loader: TestDirectionModelLoader(names: ["CNN_CNN", "RC_CNN"]), repository: repository
    )
    await selection.prepareSelection()
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = RecordingFileStore(
      fileManager: .default, userDefaults: defaults, documentsDirectory: directory)
    let selectedController = DetectionController(
      recordingFileStore: store, audioIOController: AudioIOController(userDefaults: defaults),
      modelSelection: selection, clock: FixedMeasurementClock(value: 100),
      environment: MeasurementEnvironment(
        deviceModel: "Test", osVersion: "18", appVersion: "1", buildNumber: "1")
    )
    #expect(selectedController.displayedModelName == "CNN_CNN")
    selectedController.sessionModelName = "CNN_CNN"
    selectedController.isRecording = true
    #expect(await selection.selectModel(named: "RC_CNN"))
    #expect(selectedController.displayedModelName == "CNN_CNN")
    selectedController.isRecording = false
    #expect(selectedController.displayedModelName == "RC_CNN")
  }

  @Test
  func uiCompletionIsCapturedBeforeCSVFormatting() throws {
    let orderingClock = UIOrderingClock()
    let controller = try makeController(clock: orderingClock)
    orderingClock.controller = controller
    let event = makeEvent()
    controller.isRecording = true
    controller.activeSessionID = event.sessionID
    controller.activeEvent = event
    controller.applyLocalizationResult(event)
    #expect(controller.eventcsvData.count == 1)
    controller.resultClearTask?.cancel()
  }

  @Test
  func stoppedOrReplacedSessionCannotUpdateUIOrCSV() throws {
    let controller = try makeController()
    let event = makeEvent()
    controller.isRecording = false
    controller.activeSessionID = event.sessionID
    controller.activeEvent = event
    controller.applyLocalizationResult(event)
    #expect(controller.eventcsvData.isEmpty)
    controller.isRecording = true
    controller.activeSessionID = UUID()
    controller.applyLocalizationResult(event)
    #expect(controller.currentAIAngle == nil)
    #expect(controller.eventcsvData.isEmpty)
  }

  @Test
  func failureAndCancelledEventsHaveBlankUnmeasuredDurations() throws {
    let controller = try makeController()
    var event = makeEvent()
    event.prediction = nil
    event.outcome = "cancelled"
    event.failureKind = "measurement_stopped"
    event.timing = LocalizationTiming(beepDetected: 100)
    controller.appendLocalizationEvent(event)
    let csvRow = try #require(controller.eventcsvData.first)
    let row = try #require(CSVCodec.parse(csvRow).first)
    let headers = try #require(CSVCodec.parse(DetectionCSVHeader.localization).first)
    let values = Dictionary(uniqueKeysWithValues: zip(headers, row))
    #expect(values["inference_ms"] == "")
    #expect(values["ui_update_ms"] == "")
    #expect(values["outcome"] == "cancelled")
    #expect(values["failure_kind"] == "measurement_stopped")
    #expect(values["prediction_success"] == "false")
  }

  @Test
  func failedPredictionPreparationPreservesSuccessfulFeatureMetrics() throws {
    let controller = try makeController()
    var event = makeEvent()
    event.prediction = nil
    event.timing.predictionStarted = nil
    event.timing.predictionCompleted = nil
    event.outcome = "failure"
    event.failureKind = "incompatible_input"
    controller.isRecording = true
    controller.activeSessionID = event.sessionID
    controller.activeEvent = event
    controller.applyLocalizationResult(event)
    #expect(controller.debugFeatureCreated)
    #expect(!controller.debugPredictExecuted)
    #expect(!controller.debugPredictSuccess)
    #expect(controller.state == .uncertain)
    let csvRow = try #require(controller.eventcsvData.first)
    let row = try #require(CSVCodec.parse(csvRow).first)
    let headers = try #require(CSVCodec.parse(DetectionCSVHeader.localization).first)
    let values = Dictionary(uniqueKeysWithValues: zip(headers, row))
    #expect(values["feature_extraction_ms"] == "200.000")
    #expect(values["inference_ms"] == "")
    #expect(values["ui_update_ms"] == "")
    #expect(values["outcome"] == "failure")
    controller.resultClearTask?.cancel()
  }

  private func makeController(clock: MeasurementClock = FixedMeasurementClock(value: 102.025))
    throws -> DetectionController
  {
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = RecordingFileStore(
      fileManager: .default, userDefaults: defaults, documentsDirectory: directory)
    return DetectionController(
      recordingFileStore: store, audioIOController: AudioIOController(userDefaults: defaults),
      modelSelection: DirectionModelSelectionController(
        loader: TestDirectionModelLoader(names: []), repository: MemoryModelSelectionRepository()
      ), clock: clock,
      environment: MeasurementEnvironment(
        deviceModel: "TestDevice", osVersion: "18", appVersion: "1", buildNumber: "2")
    )
  }

  private func makeEvent() -> LocalizationEvent {
    LocalizationEvent(
      sessionID: UUID(), eventID: 1, modelName: "RC_CNN", groundTruth: "45", directionTag: "45",
      origin: 100,
      timing: LocalizationTiming(
        beepDetected: 100, audioReady: 101.5, featureStarted: 101.6, featureCompleted: 101.8,
        predictionStarted: 101.9, predictionCompleted: 102
      ),
      prediction: DirectionPrediction(
        angle: 45, maxProbability: 0.8, probabilities: [0.2, 0.8, 0, 0, 0, 0, 0, 0])
    )
  }
}

private struct FixedMeasurementClock: MeasurementClock {
  let value: TimeInterval
  func now() -> TimeInterval { value }
}

// This clock is used only by the MainActor result application in the ordering test.
private final class UIOrderingClock: MeasurementClock, @unchecked Sendable {
  @MainActor weak var controller: DetectionController?

  func now() -> TimeInterval {
    MainActor.assumeIsolated {
      #expect(controller?.state == .detect)
      #expect(controller?.currentAIAngle == 45)
      #expect(controller?.eventcsvData.isEmpty == true)
      return 102.025
    }
  }
}
