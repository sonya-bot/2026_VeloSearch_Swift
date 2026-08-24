import AVFoundation
import SwiftUI

enum AnalyzeConstants {
  static let minimumFrequency = 20.0
  static let maximumFrequency = 20_000.0
  static let sweepDuration = 30.0
  static let sweepAmplitude = 0.95
  static let preSilenceDuration = 1.0
  static let postSilenceDuration = 1.0
  static let countdownSeconds = 3
  static let repeatIntervalSeconds = 3
}

struct AnalyzeMetadata: Codable {
  let formatVersion: Int
  let measurementType: String
  let directionTag: String?
  let sampleRate: Double
  let channelCount: Int
  let channelLabels: [String]
  let sweepStartFrequency: Double
  let sweepEndFrequency: Double
  let sweepDuration: Double
  let preSilenceDuration: Double
  let postSilenceDuration: Double
  let normalizationFrequency: Double
  let displaySmoothing: String
  let inputDevice: String
  let outputDevice: String
}

struct ESSCapture: Sendable {
  let sampleRate: Double
  let channels: [[Float]]
  let sweep: [Float]
}

final class ESSMeasurementService {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private var capturedChannels: [[Float]] = []
  private let captureLock = NSLock()
  private var isTapInstalled = false

  func measure(to outputURL: URL, sampleRate: Double, channelCount: Int) async throws -> ESSCapture
  {
    let input = engine.inputNode
    let inputFormat = input.inputFormat(forBus: 0)
    let actualChannelCount = min(max(Int(inputFormat.channelCount), 1), channelCount)
    capturedChannels = Array(repeating: [], count: actualChannelCount)

    let audioFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)
    input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
      guard let self else { return }
      do {
        try audioFile.write(from: buffer)
      } catch {
        AppLogger.storage.error("Analyze WAVの書き込みに失敗しました: \(error.localizedDescription)")
      }
      guard let channelData = buffer.floatChannelData else { return }
      self.captureLock.lock()
      for channelIndex in 0..<actualChannelCount {
        self.capturedChannels[channelIndex].append(
          contentsOf: UnsafeBufferPointer(
            start: channelData[channelIndex],
            count: Int(buffer.frameLength)
          )
        )
      }
      self.captureLock.unlock()
    }
    isTapInstalled = true

    if !engine.attachedNodes.contains(player) {
      engine.attach(player)
    }
    guard
      let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      )
    else {
      throw AnalyzeError.audioFormatUnavailable
    }
    engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
    let sweep = makeSweep(sampleRate: sampleRate)
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: outputFormat,
        frameCapacity: AVAudioFrameCount(sweep.count)
      ),
      let outputData = buffer.floatChannelData?[0]
    else {
      throw AnalyzeError.audioFormatUnavailable
    }
    buffer.frameLength = buffer.frameCapacity
    for index in sweep.indices { outputData[index] = sweep[index] }

    engine.prepare()
    try engine.start()
    do {
      try await Task.sleep(for: .seconds(AnalyzeConstants.preSilenceDuration))
      try Task.checkCancellation()
      player.scheduleBuffer(buffer, completionHandler: nil)
      player.play()
      try await Task.sleep(
        for: .seconds(AnalyzeConstants.sweepDuration + AnalyzeConstants.postSilenceDuration)
      )
      stop()
    } catch {
      stop()
      throw error
    }

    let channels = captureLock.withLock { capturedChannels }
    return ESSCapture(sampleRate: inputFormat.sampleRate, channels: channels, sweep: sweep)
  }

  func stop() {
    player.stop()
    if isTapInstalled {
      engine.inputNode.removeTap(onBus: 0)
      isTapInstalled = false
    }
    engine.stop()
    engine.reset()
  }

  private func makeSweep(sampleRate: Double) -> [Float] {
    let frameCount = Int(sampleRate * AnalyzeConstants.sweepDuration)
    let logarithmicRatio = log(
      AnalyzeConstants.maximumFrequency / AnalyzeConstants.minimumFrequency)
    let phaseScale =
      2 * Double.pi * AnalyzeConstants.minimumFrequency * AnalyzeConstants.sweepDuration
      / logarithmicRatio
    return (0..<frameCount).map { frameIndex in
      let time = Double(frameIndex) / sampleRate
      let phase = phaseScale * (exp(time * logarithmicRatio / AnalyzeConstants.sweepDuration) - 1)
      return Float(AnalyzeConstants.sweepAmplitude * sin(phase))
    }
  }

}

enum AnalyzeError: LocalizedError {
  case audioFormatUnavailable

  var errorDescription: String? {
    "Analyzeで使用するオーディオ形式を作成できません。"
  }
}
