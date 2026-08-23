import Foundation

struct FrequencyResponsePoint: Codable, Identifiable, Sendable {
  let frequency: Double
  let rawDecibels: Double
  let smoothedDecibels: Double

  var id: Double { frequency }
}

struct ESSChannelAnalysis: Sendable {
  let impulseResponse: [Float]
  let response: [FrequencyResponsePoint]
}

enum ESSAnalyzerError: LocalizedError {
  case emptyRecording

  var errorDescription: String? {
    "解析できる録音データがありません。"
  }
}

/// ESSと録音信号の周波数領域デコンボリューションを行う。
struct ESSAnalyzer: Sendable {
  func analyze(
    recordedChannels: [[Float]],
    sweep: [Float],
    preSilenceFrames: Int,
    sampleRate: Double
  ) throws -> [ESSChannelAnalysis] {
    guard !recordedChannels.isEmpty, recordedChannels.allSatisfy({ !$0.isEmpty }) else {
      throw ESSAnalyzerError.emptyRecording
    }

    let referenceCount = preSilenceFrames + sweep.count
    let longestCount = max(recordedChannels.map(\.count).max() ?? 0, referenceCount)
    let transformCount = nextPowerOfTwo(longestCount)
    var referenceReal = [Double](repeating: 0, count: transformCount)
    for index in sweep.indices where preSilenceFrames + index < transformCount {
      referenceReal[preSilenceFrames + index] = Double(sweep[index])
    }
    var referenceImaginary = [Double](repeating: 0, count: transformCount)
    fft(real: &referenceReal, imaginary: &referenceImaginary, inverse: false)

    return recordedChannels.map { channel in
      analyzeChannel(
        channel,
        referenceReal: referenceReal,
        referenceImaginary: referenceImaginary,
        transformCount: transformCount,
        sampleRate: sampleRate
      )
    }
  }

  private func analyzeChannel(
    _ channel: [Float],
    referenceReal: [Double],
    referenceImaginary: [Double],
    transformCount: Int,
    sampleRate: Double
  ) -> ESSChannelAnalysis {
    var recordedReal = [Double](repeating: 0, count: transformCount)
    for index in channel.indices where index < transformCount {
      recordedReal[index] = Double(channel[index])
    }
    var recordedImaginary = [Double](repeating: 0, count: transformCount)
    fft(real: &recordedReal, imaginary: &recordedImaginary, inverse: false)

    var transferReal = [Double](repeating: 0, count: transformCount)
    var transferImaginary = [Double](repeating: 0, count: transformCount)
    for index in 0..<transformCount {
      let denominator =
        referenceReal[index] * referenceReal[index]
        + referenceImaginary[index] * referenceImaginary[index]
        + 1e-12
      transferReal[index] =
        (recordedReal[index] * referenceReal[index]
          + recordedImaginary[index] * referenceImaginary[index]) / denominator
      transferImaginary[index] =
        (recordedImaginary[index] * referenceReal[index]
          - recordedReal[index] * referenceImaginary[index]) / denominator
    }

    let rawResponse = logarithmicResponse(
      real: transferReal,
      imaginary: transferImaginary,
      sampleRate: sampleRate
    )
    let normalizedResponse = normalizeAtOneKilohertz(rawResponse)
    let smoothed = smoothOneTwelfthOctave(normalizedResponse)

    fft(real: &transferReal, imaginary: &transferImaginary, inverse: true)
    let impulseResponse = transferReal.prefix(channel.count).map(Float.init)
    let response = zip(normalizedResponse, smoothed).map { raw, smooth in
      FrequencyResponsePoint(
        frequency: raw.frequency,
        rawDecibels: raw.decibels,
        smoothedDecibels: smooth
      )
    }
    return ESSChannelAnalysis(impulseResponse: impulseResponse, response: response)
  }

  private func logarithmicResponse(
    real: [Double],
    imaginary: [Double],
    sampleRate: Double
  ) -> [(frequency: Double, decibels: Double)] {
    let pointCount = 480
    let minimumFrequency = 20.0
    let maximumFrequency = min(20_000.0, sampleRate / 2)
    let ratio = maximumFrequency / minimumFrequency
    return (0..<pointCount).map { pointIndex in
      let fraction = Double(pointIndex) / Double(pointCount - 1)
      let frequency = minimumFrequency * pow(ratio, fraction)
      let bin = min(Int((frequency / sampleRate * Double(real.count)).rounded()), real.count / 2)
      let magnitude = hypot(real[bin], imaginary[bin])
      return (frequency, 20 * log10(max(magnitude, 1e-12)))
    }
  }

  private func normalizeAtOneKilohertz(
    _ response: [(frequency: Double, decibels: Double)]
  ) -> [(frequency: Double, decibels: Double)] {
    let reference =
      response.min {
        abs($0.frequency - 1_000) < abs($1.frequency - 1_000)
      }?.decibels ?? 0
    return response.map { ($0.frequency, $0.decibels - reference) }
  }

  private func smoothOneTwelfthOctave(
    _ response: [(frequency: Double, decibels: Double)]
  ) -> [Double] {
    let halfBandRatio = pow(2.0, 1.0 / 24.0)
    return response.map { point in
      let lower = point.frequency / halfBandRatio
      let upper = point.frequency * halfBandRatio
      let values = response.lazy
        .filter { $0.frequency >= lower && $0.frequency <= upper }
        .map(\.decibels)
      return values.reduce(0, +) / Double(max(values.count, 1))
    }
  }

  private func nextPowerOfTwo(_ value: Int) -> Int {
    var result = 1
    while result < value { result <<= 1 }
    return result
  }

  private func fft(real: inout [Double], imaginary: inout [Double], inverse: Bool) {
    let count = real.count
    var reversedIndex = 0
    for index in 1..<count {
      var bit = count >> 1
      while reversedIndex & bit != 0 {
        reversedIndex ^= bit
        bit >>= 1
      }
      reversedIndex ^= bit
      if index < reversedIndex {
        real.swapAt(index, reversedIndex)
        imaginary.swapAt(index, reversedIndex)
      }
    }

    var length = 2
    while length <= count {
      let angle = (inverse ? 2.0 : -2.0) * Double.pi / Double(length)
      let baseReal = cos(angle)
      let baseImaginary = sin(angle)
      for start in stride(from: 0, to: count, by: length) {
        var twiddleReal = 1.0
        var twiddleImaginary = 0.0
        for offset in 0..<(length / 2) {
          let evenIndex = start + offset
          let oddIndex = evenIndex + length / 2
          let oddReal = real[oddIndex] * twiddleReal - imaginary[oddIndex] * twiddleImaginary
          let oddImaginary = real[oddIndex] * twiddleImaginary + imaginary[oddIndex] * twiddleReal
          real[oddIndex] = real[evenIndex] - oddReal
          imaginary[oddIndex] = imaginary[evenIndex] - oddImaginary
          real[evenIndex] += oddReal
          imaginary[evenIndex] += oddImaginary
          let nextReal = twiddleReal * baseReal - twiddleImaginary * baseImaginary
          twiddleImaginary = twiddleReal * baseImaginary + twiddleImaginary * baseReal
          twiddleReal = nextReal
        }
      }
      length <<= 1
    }

    if inverse {
      for index in 0..<count {
        real[index] /= Double(count)
        imaginary[index] /= Double(count)
      }
    }
  }
}
