import Foundation
import Observation

@MainActor
@Observable
final class DirectionModelSelectionController {
  static let defaultModelName = "20260725-010849_hybrid_Best_model_epoch59"
  let detectionThreshold: Float = 0.40
  let resources: [DirectionModelResource]
  private(set) var selectedModelName: String?
  private(set) var predictor: DirectionPredicting?
  private(set) var isLoading = false
  private(set) var isMeasurementActive = false
  var message: String?

  private let loader: DirectionModelLoading
  private let repository: DirectionModelSelectionPersisting
  private var hasPreparedSelection = false

  var canStartMeasurement: Bool { predictor != nil && !isLoading && !isMeasurementActive }
  var canSelectModel: Bool { !isLoading && !isMeasurementActive }

  init(loader: DirectionModelLoading, repository: DirectionModelSelectionPersisting) {
    self.loader = loader
    self.repository = repository
    resources = loader.resources
  }

  func prepareSelection() async {
    guard !hasPreparedSelection else { return }
    hasPreparedSelection = true
    let requestedName = repository.selectedModelName ?? Self.defaultModelName
    if await selectModel(named: requestedName) { return }
    if requestedName != Self.defaultModelName {
      if await selectModel(named: Self.defaultModelName) {
        message = "保存済みモデルを利用できないため、現行モデルへ戻しました。"
        return
      }
    }
    message = "利用可能な推論モデルがありません。Settingsでモデルを確認してください。"
  }

  @discardableResult
  func selectModel(named name: String) async -> Bool {
    guard canSelectModel else { return false }
    guard let resource = resources.first(where: { $0.id == name }),
      resources.filter({ $0.id == name }).count == 1
    else {
      message = "指定したモデルが同梱されていないか、モデル名が重複しています。"
      return false
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let loadedModel = try await loader.load(resource)
      predictor = loadedModel
      selectedModelName = resource.id
      repository.selectedModelName = resource.id
      message = nil
      return true
    } catch {
      AppLogger.detection.error("モデルの読み込み・検証に失敗しました: \(error.localizedDescription)")
      message = (error as? DirectionModelError)?.errorDescription ?? "推論モデルを読み込めませんでした。"
      return false
    }
  }

  func beginMeasurement() -> Bool {
    guard canStartMeasurement else { return false }
    isMeasurementActive = true
    return true
  }

  func endMeasurement() { isMeasurementActive = false }
}
