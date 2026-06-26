import Foundation
import CoreML

class MLModelManager {
    private var model: _20260611_01_Best_hybrid_model_epoch90?
    let detectionThreshold: Float = 50.0 // しきい値 50%
    
    init() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            self.model = try _20260611_01_Best_hybrid_model_epoch90(configuration: config)
        } catch {
            print("Core MLモデルロード失敗: \(error)")
        }
    }
    
    func predict(features: MLMultiArray) -> (angle: Int, probability: Float)? {
        guard let model = model else { return nil }

        do {
            let input = _20260611_01_Best_hybrid_model_epoch90Input(audioFeatures: features)
            let output = try model.prediction(input: input)

            // デバッグ用
            // print("===== CoreML Output =====")

            var maxProb: Float = 0.0
            var maxIndex = 0

            for i in 0..<8 {
                let logProb = output.directionProbabilities[i].floatValue
                let prob = exp(logProb) * 100.0

                // print("Class \(i): \(prob)%")

                if prob > maxProb {
                    maxProb = prob
                    maxIndex = i
                }
            }

            // print("Max = \(maxProb)%, index = \(maxIndex)")

            return (maxIndex * 45, maxProb)

        } catch {
            print("推論エラー: \(error)")
            return nil
        }
    }
}