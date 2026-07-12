import AVFoundation
import Foundation

final class BeepDetector {
    private let sampleRate: Double = 44100.0
    private let minimumDecibel: Float = -60.0
    private let minimumBandRatio: Float = 5.0
    private let requiredConsecutiveHits = 3
    // 実験用ビープ音は2秒のため、同一ビープ中の再検知を避ける。
    private let cooldownSeconds: TimeInterval = 2.2
    private let targetFrequencies: [Double] = [420, 430, 440, 450, 460]
    private let guardFrequencies: [Double] = [250, 300, 600, 700, 900, 1200]

    private var consecutiveHits = 0
    private var lastDetectionTime: Date?

    func detect(buffer: AVAudioPCMBuffer, at time: Date = Date()) -> Bool {
        if let lastDetectionTime, time.timeIntervalSince(lastDetectionTime) < cooldownSeconds {
            return false
        }

        guard let channelData = buffer.floatChannelData else { return false }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return false }

        let left = channelData[0]
        let right = buffer.format.channelCount > 1 ? channelData[1] : channelData[0]
        var mono = [Float](repeating: 0.0, count: frameLength)

        for index in 0..<frameLength {
            mono[index] = (left[index] + right[index]) * 0.5
        }

        let rms = sqrt(mono.reduce(Float(0.0)) { $0 + ($1 * $1) } / Float(frameLength))
        let decibel = 20.0 * log10(max(rms, 0.000_001))

        let targetPower = targetFrequencies.reduce(Float(0.0)) {
            $0 + goertzelPower(samples: mono, frequency: $1)
        }
        let guardPower = guardFrequencies.reduce(Float(0.0)) {
            $0 + goertzelPower(samples: mono, frequency: $1)
        }
        let bandRatio = targetPower / max(guardPower, 0.000_001)

        if decibel >= minimumDecibel && bandRatio >= minimumBandRatio {
            consecutiveHits += 1
        } else {
            consecutiveHits = 0
        }

        guard consecutiveHits >= requiredConsecutiveHits else { return false }

        consecutiveHits = 0
        lastDetectionTime = time
        return true
    }

    func reset() {
        consecutiveHits = 0
        lastDetectionTime = nil
    }

    private func goertzelPower(samples: [Float], frequency: Double) -> Float {
        let normalizedFrequency = frequency / sampleRate
        let coefficient = Float(2.0 * cos(2.0 * Double.pi * normalizedFrequency))
        var previous: Float = 0.0
        var previous2: Float = 0.0

        for sample in samples {
            let current = sample + coefficient * previous - previous2
            previous2 = previous
            previous = current
        }

        return previous2 * previous2 + previous * previous - coefficient * previous * previous2
    }
}
