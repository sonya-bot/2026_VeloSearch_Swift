import CoreML
import Foundation

struct DirectionPrediction {
  let angle: Int
  let maxProbability: Float
  let probabilities: [Float]
}

struct DirectionInferenceResult {
  let prediction: DirectionPrediction?
  let started: TimeInterval?
  let completed: TimeInterval?
  let failureKind: String
}

protocol DirectionPredicting: AnyObject, Sendable {
  func infer(features: MLMultiArray, clock: MeasurementClock) -> DirectionInferenceResult
}

enum DirectionModelError: LocalizedError {
  case incompatibleInput
  case incompatibleOutput
  case invalidProbabilities

  var errorDescription: String? {
    switch self {
    case .incompatibleInput: return "モデルの入力が対応する特徴量形式と一致しません。"
    case .incompatibleOutput: return "モデルの出力が8方向の確率形式と一致しません。"
    case .invalidProbabilities: return "モデルが有効な8方向の確率を返しませんでした。"
    }
  }
}

// Protect Core ML execution even if different recording controllers share this loaded model.
final class DirectionModelService: DirectionPredicting, @unchecked Sendable {
  private let inferenceLock = NSLock()
  private let model: MLModel
  private let inputName: String
  private let outputName: String
  private let inputDataType: MLMultiArrayDataType

  init(url: URL) throws {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .all
    model = try MLModel(contentsOf: url, configuration: configuration)
    let inputs = model.modelDescription.inputDescriptionsByName
    guard inputs.count == 1, let input = inputs.first,
      let constraint = input.value.multiArrayConstraint,
      constraint.shape.map(\.intValue) == [1, 5, 64, 173],
      [.float16, .float32, .double].contains(constraint.dataType)
    else { throw DirectionModelError.incompatibleInput }
    let outputs = model.modelDescription.outputDescriptionsByName
    guard outputs.count == 1, let output = outputs.first,
      let outputConstraint = output.value.multiArrayConstraint,
      outputConstraint.shape.reduce(1, { $0 * $1.intValue }) == 8
    else { throw DirectionModelError.incompatibleOutput }
    inputName = input.key
    outputName = output.key
    inputDataType = constraint.dataType
  }

  func infer(features: MLMultiArray, clock: MeasurementClock) -> DirectionInferenceResult {
    inferenceLock.lock()
    defer { inferenceLock.unlock() }
    var started: TimeInterval?
    var completed: TimeInterval?
    do {
      let provider = try inputProvider(features: features)
      started = clock.now()
      let output: MLFeatureProvider
      do {
        output = try model.prediction(from: provider)
        completed = clock.now()
      } catch {
        completed = clock.now()
        throw error
      }
      let prediction = try directionPrediction(from: output)
      return DirectionInferenceResult(
        prediction: prediction, started: started, completed: completed, failureKind: ""
      )
    } catch {
      AppLogger.detection.error("推論に失敗しました: \(error.localizedDescription)")
      let failureKind: String
      switch error {
      case DirectionModelError.invalidProbabilities: failureKind = "invalid_probabilities"
      case DirectionModelError.incompatibleInput: failureKind = "incompatible_input"
      case DirectionModelError.incompatibleOutput: failureKind = "incompatible_output"
      default: failureKind = "prediction_failed"
      }
      return DirectionInferenceResult(
        prediction: nil, started: started, completed: completed, failureKind: failureKind
      )
    }
  }

  private func inputProvider(features: MLMultiArray) throws -> MLFeatureProvider {
    guard features.shape.map(\.intValue) == [1, 5, 64, 173] else {
      throw DirectionModelError.incompatibleInput
    }
    let inputFeatures: MLMultiArray
    if features.dataType == inputDataType {
      inputFeatures = features
    } else {
      inputFeatures = try MLMultiArray(shape: features.shape, dataType: inputDataType)
      for index in 0..<features.count { inputFeatures[index] = features[index] }
    }
    return try MLDictionaryFeatureProvider(dictionary: [inputName: inputFeatures])
  }

  private func directionPrediction(from output: MLFeatureProvider) throws -> DirectionPrediction {
    guard let probabilitiesArray = output.featureValue(for: outputName)?.multiArrayValue,
      probabilitiesArray.count == 8
    else { throw DirectionModelError.incompatibleOutput }
    let probabilities = (0..<8).map { probabilitiesArray[$0].floatValue }
    guard probabilities.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
      let maxIndex = probabilities.indices.max(by: { probabilities[$0] < probabilities[$1] })
    else { throw DirectionModelError.invalidProbabilities }
    return DirectionPrediction(
      angle: maxIndex * 45, maxProbability: probabilities[maxIndex], probabilities: probabilities
    )
  }
}
