import Foundation
import CoreML

struct DirectionPrediction {
    let angle: Int
    let maxProbability: Float
    let probabilities: [Float]
}

class MLModelManager {
    static let modelName = "20260725-010849_hybrid_Best_model_epoch59"

    private var model: _20260725_010849_hybrid_Best_model_epoch59?
    let detectionThreshold: Float = 0.40
    
    init() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            self.model = try _20260725_010849_hybrid_Best_model_epoch59(configuration: config)
        } catch {
            print("Core MLモデルロード失敗: \(error)")
        }
    }
    
    func predict(features: MLMultiArray) -> DirectionPrediction? {
        guard let model = model else { return nil }

        do {
            let input = _20260725_010849_hybrid_Best_model_epoch59Input(audioFeatures: features)
            let output = try model.prediction(input: input)

            guard output.directionProbabilities.count == 8 else {
                print("推論出力数が不正です: \(output.directionProbabilities.count)")
                return nil
            }

            let probabilities = (0..<8).map {
                output.directionProbabilities[$0].floatValue
            }
            guard probabilities.allSatisfy({ $0.isFinite && $0 >= 0.0 }) else {
                print("推論確率に不正な値が含まれています")
                return nil
            }

            guard let maxIndex = probabilities.indices.max(
                by: { probabilities[$0] < probabilities[$1] }
            ) else {
                return nil
            }

            return DirectionPrediction(
                angle: maxIndex * 45,
                maxProbability: probabilities[maxIndex],
                probabilities: probabilities
            )

        } catch {
            print("推論エラー: \(error)")
            return nil
        }
    }
}
