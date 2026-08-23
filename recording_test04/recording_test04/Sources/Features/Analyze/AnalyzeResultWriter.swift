import AVFoundation
import Foundation

protocol AnalyzeResultWriting {
  func write(
    _ results: [ESSChannelAnalysis],
    recordingURL: URL,
    sampleRate: Double,
    configuration: ActiveAudioConfiguration,
    directionTag: MeasurementDirectionTag
  ) throws
}

struct AnalyzeResultWriter: AnalyzeResultWriting {
  func write(
    _ results: [ESSChannelAnalysis],
    recordingURL: URL,
    sampleRate: Double,
    configuration: ActiveAudioConfiguration,
    directionTag: MeasurementDirectionTag
  ) throws {
    let baseURL = recordingURL.deletingPathExtension()
    try responseCSV(for: results).write(
      to: baseURL.appendingPathExtension("csv"),
      atomically: true,
      encoding: .utf8
    )
    try metadataData(
      results: results,
      sampleRate: sampleRate,
      configuration: configuration,
      directionTag: directionTag
    ).write(to: baseURL.appendingPathExtension("json"))

    for (channelIndex, result) in results.enumerated() {
      let impulseURL = baseURL.deletingLastPathComponent().appendingPathComponent(
        "\(baseURL.lastPathComponent)_IR_CH\(channelIndex + 1).wav"
      )
      try writeImpulseResponse(result.impulseResponse, to: impulseURL, sampleRate: sampleRate)
    }
  }

  private func responseCSV(for results: [ESSChannelAnalysis]) -> String {
    var csv = "frequency_hz"
    for channelIndex in results.indices {
      csv += ",ch\(channelIndex + 1)_raw_db,ch\(channelIndex + 1)_smoothed_db"
    }
    csv += "\n"
    let pointCount = results.map(\.response.count).min() ?? 0
    for pointIndex in 0..<pointCount {
      csv += String(format: "%.3f", results[0].response[pointIndex].frequency)
      for result in results {
        let point = result.response[pointIndex]
        csv += String(format: ",%.6f,%.6f", point.rawDecibels, point.smoothedDecibels)
      }
      csv += "\n"
    }
    return csv
  }

  private func metadataData(
    results: [ESSChannelAnalysis],
    sampleRate: Double,
    configuration: ActiveAudioConfiguration,
    directionTag: MeasurementDirectionTag
  ) throws -> Data {
    let labels: [String]
    if configuration.isBuiltInInput && configuration.channelCount >= 2 {
      labels = configuration.micSource == .back ? ["Back", "Bottom"] : ["Front", "Bottom"]
    } else if configuration.channelCount >= 2 {
      labels = ["L", "R"]
    } else {
      labels = ["Mono"]
    }
    let metadata = AnalyzeMetadata(
      formatVersion: 1,
      measurementType: "ESS",
      directionTag: directionTag == .none ? nil : directionTag.rawValue,
      sampleRate: sampleRate,
      channelCount: results.count,
      channelLabels: Array(labels.prefix(results.count)),
      sweepStartFrequency: AnalyzeConstants.minimumFrequency,
      sweepEndFrequency: AnalyzeConstants.maximumFrequency,
      sweepDuration: AnalyzeConstants.sweepDuration,
      preSilenceDuration: AnalyzeConstants.preSilenceDuration,
      postSilenceDuration: AnalyzeConstants.postSilenceDuration,
      normalizationFrequency: 1_000,
      displaySmoothing: "1/12 octave",
      inputDevice: configuration.inputName,
      outputDevice: configuration.outputName
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(metadata)
  }

  private func writeImpulseResponse(_ samples: [Float], to url: URL, sampleRate: Double) throws {
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      ),
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(samples.count)
      ),
      let channel = buffer.floatChannelData?[0]
    else { throw AnalyzeError.audioFormatUnavailable }
    buffer.frameLength = buffer.frameCapacity
    for index in samples.indices { channel[index] = samples[index] }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
  }
}
