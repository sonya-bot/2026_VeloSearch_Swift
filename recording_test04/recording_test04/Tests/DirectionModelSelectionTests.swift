import CoreML
import Foundation
import Testing

@testable import recording_test04

@MainActor
struct DirectionModelSelectionTests {
  @Test
  func modelNameRemovesOnlyFinalExtension() {
    let resource = DirectionModelResource(url: URL(fileURLWithPath: "/models/RC_CNN.v2.mlmodelc"))
    #expect(resource.id == "RC_CNN.v2")
  }

  @Test
  func successfulSelectionPersistsAndRejectsChangesDuringMeasurement() async throws {
    let repository = MemoryModelSelectionRepository()
    let loader = TestDirectionModelLoader(names: [
      DirectionModelSelectionController.defaultModelName, "RC_CNN",
    ])
    let controller = DirectionModelSelectionController(loader: loader, repository: repository)
    await controller.prepareSelection()
    #expect(await controller.selectModel(named: "RC_CNN"))
    #expect(repository.selectedModelName == "RC_CNN")
    #expect(controller.beginMeasurement())
    #expect(
      !(await controller.selectModel(named: DirectionModelSelectionController.defaultModelName)))
    #expect(controller.selectedModelName == "RC_CNN")
    controller.endMeasurement()
    let restarted = DirectionModelSelectionController(loader: loader, repository: repository)
    await restarted.prepareSelection()
    #expect(restarted.selectedModelName == "RC_CNN")
  }

  @Test
  func loadingFailureKeepsPreviousSelectionAndMissingStoredModelFallsBack() async {
    let repository = MemoryModelSelectionRepository()
    let loader = TestDirectionModelLoader(names: [
      DirectionModelSelectionController.defaultModelName, "Broken",
    ])
    loader.failingNames = ["Broken"]
    let controller = DirectionModelSelectionController(loader: loader, repository: repository)
    await controller.prepareSelection()
    #expect(!(await controller.selectModel(named: "Broken")))
    #expect(controller.selectedModelName == DirectionModelSelectionController.defaultModelName)
    #expect(controller.message != nil)
    repository.selectedModelName = "Missing"
    let restarted = DirectionModelSelectionController(loader: loader, repository: repository)
    await restarted.prepareSelection()
    #expect(restarted.selectedModelName == DirectionModelSelectionController.defaultModelName)
    #expect(restarted.message != nil)
  }

  @Test
  func noUsableModelPreventsMeasurement() async {
    let loader = TestDirectionModelLoader(names: [
      DirectionModelSelectionController.defaultModelName
    ])
    loader.failingNames = [DirectionModelSelectionController.defaultModelName]
    let controller = DirectionModelSelectionController(
      loader: loader, repository: MemoryModelSelectionRepository())
    await controller.prepareSelection()
    #expect(!controller.canStartMeasurement)
    #expect(!controller.beginMeasurement())
    #expect(controller.message != nil)
  }

  @Test
  func legacySelectionMigratesToCNNWithoutChangingExperimentModel() async {
    let repository = MemoryModelSelectionRepository()
    repository.selectedModelName = DirectionModelSelectionController.legacyModelName
    let controller = DirectionModelSelectionController(
      loader: TestDirectionModelLoader(names: ["CNN_CNN", "CNN_RC", "RC_CNN", "RC_RC"]),
      repository: repository
    )
    await controller.prepareSelection()
    #expect(controller.selectedModelName == "CNN_CNN")
    #expect(repository.selectedModelName == "CNN_CNN")
    #expect(controller.message == nil)
  }

  @Test
  func failedLegacyMigrationDoesNotPersistAnUnusableModel() async {
    let repository = MemoryModelSelectionRepository()
    repository.selectedModelName = DirectionModelSelectionController.legacyModelName
    let loader = TestDirectionModelLoader(names: ["CNN_CNN"])
    loader.failingNames = ["CNN_CNN"]
    let controller = DirectionModelSelectionController(loader: loader, repository: repository)
    await controller.prepareSelection()
    #expect(!controller.canStartMeasurement)
    #expect(repository.selectedModelName == DirectionModelSelectionController.legacyModelName)
  }

  @Test
  func bundleContainsExactlyFourComparisonModels() {
    let loader = DirectionModelLoadingService(bundle: .main)
    #expect(loader.resources.map(\.id) == ["CNN_CNN", "CNN_RC", "RC_CNN", "RC_RC"])
  }

  @Test(arguments: ["CNN_CNN", "CNN_RC", "RC_CNN", "RC_RC"])
  func bundledComparisonModelHasCompatibleInterface(modelName: String) async throws {
    let loader = DirectionModelLoadingService(bundle: .main)
    let resource = try #require(loader.resources.first { $0.id == modelName })
    let predictor = try await loader.load(resource)
    let features = try MLMultiArray(shape: [1, 5, 64, 173], dataType: .float16)
    for index in 0..<features.count { features[index] = 0 }
    let result = predictor.infer(features: features, clock: SystemMeasurementClock())
    let prediction = try #require(result.prediction)
    #expect(prediction.probabilities.count == 8)
    #expect(prediction.angle >= 0 && prediction.angle <= 315 && prediction.angle % 45 == 0)
    #expect(result.started != nil && result.completed != nil)
    let repeatedResult = predictor.infer(features: features, clock: SystemMeasurementClock())
    let repeatedPrediction = try #require(repeatedResult.prediction)
    #expect(
      zip(prediction.probabilities, repeatedPrediction.probabilities).allSatisfy {
        abs($0 - $1) < 0.001
      })
    let invalidFeatures = try MLMultiArray(shape: [1, 2], dataType: .float16)
    let invalidResult = predictor.infer(features: invalidFeatures, clock: SystemMeasurementClock())
    #expect(invalidResult.failureKind == "incompatible_input")
    #expect(invalidResult.started == nil && invalidResult.completed == nil)
  }
}

final class MemoryModelSelectionRepository: DirectionModelSelectionPersisting {
  var selectedModelName: String?
}

final class TestDirectionModelLoader: DirectionModelLoading {
  let resources: [DirectionModelResource]
  var failingNames: Set<String> = []

  init(names: [String]) {
    resources = names.map {
      DirectionModelResource(url: URL(fileURLWithPath: "/models/\($0).mlmodelc"))
    }
  }

  func load(_ resource: DirectionModelResource) async throws -> DirectionPredicting {
    if failingNames.contains(resource.id) { throw DirectionModelError.incompatibleInput }
    return TestDirectionPredictor()
  }
}

final class TestDirectionPredictor: DirectionPredicting {
  func infer(features: MLMultiArray, clock: MeasurementClock) -> DirectionInferenceResult {
    DirectionInferenceResult(
      prediction: DirectionPrediction(
        angle: 0, maxProbability: 0.8, probabilities: [0.8, 0.2, 0, 0, 0, 0, 0, 0]),
      started: clock.now(), completed: clock.now(), failureKind: ""
    )
  }
}
