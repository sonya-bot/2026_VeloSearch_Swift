import AVFoundation
import SwiftUI

private enum AnalyzeConstants {
  static let minimumFrequency = 20.0
  static let maximumFrequency = 20_000.0
  static let sweepDuration = 10.0
  static let preSilenceDuration = 1.0
  static let postSilenceDuration = 2.0
  static let countdownSeconds = 3
  static let repeatIntervalSeconds = 3
}

private struct AnalyzeMetadata: Codable {
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

private struct ESSCapture: Sendable {
  let sampleRate: Double
  let channels: [[Float]]
  let sweep: [Float]
}

private final class ESSMeasurementService {
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
      await player.scheduleBuffer(buffer)
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
      let fadeFrames = max(Int(sampleRate * 0.02), 1)
      let fadeIn = min(Double(frameIndex) / Double(fadeFrames), 1)
      let fadeOut = min(Double(frameCount - frameIndex - 1) / Double(fadeFrames), 1)
      return Float(0.25 * min(fadeIn, fadeOut) * sin(phase))
    }
  }
}

private enum AnalyzeError: LocalizedError {
  case audioFormatUnavailable

  var errorDescription: String? {
    "Analyzeで使用するオーディオ形式を作成できません。"
  }
}

@MainActor
private final class AnalyzeController: ObservableObject {
  enum State: Equatable {
    case standby
    case countdown(Int)
    case measuring(Int, Int)
    case analyzing(Int, Int)
    case completed
    case failed(String)

    var title: String {
      switch self {
      case .standby: return "Standby"
      case .countdown(let seconds): return "Starts in \(seconds)"
      case .measuring(let current, let total): return "Measuring \(current) / \(total)"
      case .analyzing(let current, let total): return "Analyzing \(current) / \(total)"
      case .completed: return "Completed"
      case .failed(let message): return message
      }
    }
  }

  @Published private(set) var state: State = .standby
  @Published private(set) var analyses: [ESSChannelAnalysis] = []
  @Published private(set) var waveformChannels: [[Float]] = []
  @Published private(set) var clippingWarning = false
  @Published private(set) var peakDecibels: Double?

  private let recordingFileStore: RecordingFileStoring
  private let audioIOController: AudioIOController
  private let service = ESSMeasurementService()
  private let analyzer = ESSAnalyzer()
  private var executionTask: Task<Void, Never>?

  init(recordingFileStore: RecordingFileStoring, audioIOController: AudioIOController) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
  }

  var isRunning: Bool {
    switch state {
    case .countdown, .measuring, .analyzing: return true
    default: return false
    }
  }

  func start(repeatCount: Int, directionTag: MeasurementDirectionTag) {
    guard !isRunning else { return }
    executionTask = Task { [weak self] in
      guard let self else { return }
      do {
        for term in 1...repeatCount {
          try await countdown()
          try Task.checkCancellation()
          let configuration = try audioIOController.configureForRecording(allowsPlayback: true)
          state = .measuring(term, repeatCount)
          let recordingFile = try recordingFileStore.makeRecordingURL(prefix: "Analyze")
          let capture = try await service.measure(
            to: recordingFile.url,
            sampleRate: configuration.sampleRate,
            channelCount: configuration.channelCount
          )
          waveformChannels = capture.channels
          let peak = capture.channels.flatMap { $0 }.map { abs(Double($0)) }.max() ?? 0
          peakDecibels = peak > 0 ? 20 * log10(peak) : nil
          clippingWarning = peak >= 0.891
          state = .analyzing(term, repeatCount)
          let analysisEngine = analyzer
          let result = try await Task.detached {
            try analysisEngine.analyze(
              recordedChannels: capture.channels,
              sweep: capture.sweep,
              preSilenceFrames: Int(capture.sampleRate * AnalyzeConstants.preSilenceDuration),
              sampleRate: capture.sampleRate
            )
          }.value
          analyses = result
          try saveAnalysis(
            result,
            recordingURL: recordingFile.url,
            sampleRate: capture.sampleRate,
            configuration: configuration,
            directionTag: directionTag
          )
          if term < repeatCount {
            try await Task.sleep(for: .seconds(AnalyzeConstants.repeatIntervalSeconds))
          }
        }
        state = .completed
      } catch is CancellationError {
        state = .standby
      } catch {
        state = .failed(error.localizedDescription)
      }
      executionTask = nil
    }
  }

  func stop() {
    executionTask?.cancel()
    service.stop()
    executionTask = nil
    state = .standby
  }

  private func countdown() async throws {
    for seconds in stride(from: AnalyzeConstants.countdownSeconds, through: 1, by: -1) {
      state = .countdown(seconds)
      try await Task.sleep(for: .seconds(1))
    }
  }

  private func saveAnalysis(
    _ results: [ESSChannelAnalysis],
    recordingURL: URL,
    sampleRate: Double,
    configuration: ActiveAudioConfiguration,
    directionTag: MeasurementDirectionTag
  ) throws {
    let baseURL = recordingURL.deletingPathExtension()
    let labels: [String]
    if configuration.isBuiltInInput && configuration.channelCount >= 2 {
      labels = configuration.micSource == .back ? ["Back", "Bottom"] : ["Front", "Bottom"]
    } else if configuration.channelCount >= 2 {
      labels = ["L", "R"]
    } else {
      labels = ["Mono"]
    }

    var csv = "frequency_hz"
    for channelIndex in results.indices {
      csv += ",ch\(channelIndex + 1)_raw_db,ch\(channelIndex + 1)_smoothed_db"
    }
    csv += "\n"
    let pointCount = results.map { $0.response.count }.min() ?? 0
    for pointIndex in 0..<pointCount {
      csv += String(format: "%.3f", results[0].response[pointIndex].frequency)
      for result in results {
        let point = result.response[pointIndex]
        csv += String(format: ",%.6f,%.6f", point.rawDecibels, point.smoothedDecibels)
      }
      csv += "\n"
    }
    try csv.write(to: baseURL.appendingPathExtension("csv"), atomically: true, encoding: .utf8)

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
    try encoder.encode(metadata).write(to: baseURL.appendingPathExtension("json"))

    for (channelIndex, result) in results.enumerated() {
      let impulseURL =
        baseURL
        .deletingLastPathComponent()
        .appendingPathComponent("\(baseURL.lastPathComponent)_IR_CH\(channelIndex + 1).wav")
      try writeImpulseResponse(
        result.impulseResponse, to: impulseURL, sampleRate: sampleRate)
    }
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

struct AnalyzeView: View {
  @StateObject private var controller: AnalyzeController
  @ObservedObject private var audioIOController: AudioIOController
  private let recordingFileStore: RecordingFileStoring
  @AppStorage("selectedSceneFolderName") private var selectedScene = RecordingFileStore
    .defaultSceneName
  @AppStorage("measurementDirectionTag") private var directionTag = MeasurementDirectionTag.none
  @AppStorage("analyzeRepeatCount") private var repeatCount = 1
  @AppStorage("recordingChannelMode") private var channelMode = RecordingChannelMode.automatic

  init(
    recordingFileStore: RecordingFileStoring,
    userDefaults: UserDefaults,
    audioIOController: AudioIOController
  ) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
    _controller = StateObject(
      wrappedValue: AnalyzeController(
        recordingFileStore: recordingFileStore,
        audioIOController: audioIOController
      )
    )
    _selectedScene = AppStorage(
      wrappedValue: RecordingFileStore.defaultSceneName,
      "selectedSceneFolderName",
      store: userDefaults
    )
    _directionTag = AppStorage(
      wrappedValue: .none,
      "measurementDirectionTag",
      store: userDefaults
    )
    _repeatCount = AppStorage(wrappedValue: 1, "analyzeRepeatCount", store: userDefaults)
    _channelMode = AppStorage(
      wrappedValue: .automatic,
      "recordingChannelMode",
      store: userDefaults
    )
  }

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        let isLandscape = geometry.size.width > geometry.size.height
        Group {
          if isLandscape {
            HStack(spacing: 12) {
              VStack(spacing: 8) {
                analyzeStatusPanel
                Spacer(minLength: 0)
                measurementButton
                Spacer(minLength: 0)
              }
              .frame(width: (geometry.size.width - 12) / 3)

              VStack(spacing: 8) {
                AudioRouteStatusButton(
                  audioIOController: audioIOController,
                  displayMode: .compact
                )
                measurementSettings(isCompact: true)
                waveformSection
                  .frame(height: waveformDisplayCount >= 2 ? 62 : 38)
                responseGraph
              }
              .frame(width: (geometry.size.width - 12) * 2 / 3)
            }
          } else {
            VStack(spacing: 8) {
              AudioRouteStatusButton(audioIOController: audioIOController)
              measurementSettings(isCompact: false)
              waveformSection
                .frame(height: waveformDisplayCount >= 2 ? 120 : 70)
              responseGraph
              HStack(spacing: 12) {
                analyzeStatusPanel
                measurementButton
              }
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle("Analyze")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  @ViewBuilder
  private func measurementSettings(isCompact: Bool) -> some View {
    if isCompact {
      HStack(spacing: 6) {
        MeasurementDestinationPicker(
          recordingFileStore: recordingFileStore,
          selection: $selectedScene,
          isDisabled: controller.isRunning
        )
        MeasurementDirectionPicker(selection: $directionTag, isDisabled: controller.isRunning)
        repeatStepper
      }
    } else {
      VStack(spacing: 7) {
        MeasurementDestinationPicker(
          recordingFileStore: recordingFileStore,
          selection: $selectedScene,
          isDisabled: controller.isRunning
        )
        HStack(spacing: 8) {
          MeasurementDirectionPicker(selection: $directionTag, isDisabled: controller.isRunning)
          repeatStepper
        }
        Text("所要時間 約 \(estimatedSeconds) 秒")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var repeatStepper: some View {
    Stepper("回数  \(repeatCount)", value: $repeatCount, in: 1...99)
      .disabled(controller.isRunning)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .padding(.horizontal, 10)
      .frame(height: 48)
      .background(Color(uiColor: .secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private var analyzeStatusPanel: some View {
    VStack(spacing: 6) {
      Text(controller.state.title)
        .font(.headline)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      if controller.clippingWarning {
        Label("Clipping (-1 dBFS以上)", systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
      } else if let peakDecibels = controller.peakDecibels {
        Text(
          peakDecibels >= -24 && peakDecibels <= -6
            ? String(format: "Peak %.1f dBFS · Target内", peakDecibels)
            : String(format: "Peak %.1f dBFS · Target -24〜-6", peakDecibels)
        )
        .font(.caption)
        .foregroundStyle(
          peakDecibels >= -24 && peakDecibels <= -6 ? Color.secondary : Color.orange)
      }
      if let issue = audioIOController.configurationIssue(allowsPlayback: true) {
        Text(issue)
          .font(.caption2)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private var measurementButton: some View {
    MeasurementControlButton(
      idleTitle: "Start",
      activeTitle: "Stop",
      isActive: controller.isRunning,
      tint: .red,
      isDisabled: !controller.isRunning
        && audioIOController.configurationIssue(allowsPlayback: true) != nil
    ) {
      if controller.isRunning {
        controller.stop()
      } else {
        controller.start(repeatCount: repeatCount, directionTag: directionTag)
      }
    }
  }

  private var estimatedSeconds: Int {
    let oneTerm =
      AnalyzeConstants.countdownSeconds
      + Int(
        AnalyzeConstants.preSilenceDuration + AnalyzeConstants.sweepDuration
          + AnalyzeConstants.postSilenceDuration)
    return oneTerm * repeatCount + AnalyzeConstants.repeatIntervalSeconds * max(repeatCount - 1, 0)
  }

  private var waveformSection: some View {
    VStack(spacing: 3) {
      ForEach(0..<waveformDisplayCount, id: \.self) { channelIndex in
        AnalyzeWaveform(
          samples: controller.waveformChannels.indices.contains(channelIndex)
            ? controller.waveformChannels[channelIndex] : []
        )
        .overlay(alignment: .topLeading) {
          Text("CH\(channelIndex + 1)").font(.caption2).padding(3)
        }
      }
    }
  }

  private var waveformDisplayCount: Int {
    if !controller.waveformChannels.isEmpty {
      return min(controller.waveformChannels.count, 2)
    }
    switch channelMode {
    case .mono: return 1
    case .stereo: return 2
    case .automatic: return audioIOController.activeConfiguration.channelCount >= 2 ? 2 : 1
    }
  }

  private var responseGraph: some View {
    FrequencyResponseGraph(channels: controller.analyses.map(\.response))
      .background(Color(uiColor: .secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

private struct AnalyzeWaveform: View {
  let samples: [Float]

  var body: some View {
    Canvas { context, size in
      var path = Path()
      let center = size.height / 2
      let sampleCount = max(samples.count, 1)
      let strideSize = max(sampleCount / max(Int(size.width), 1), 1)
      for (pointIndex, sampleIndex) in stride(from: 0, to: samples.count, by: strideSize)
        .enumerated()
      {
        let x = CGFloat(pointIndex) / CGFloat(max(samples.count / strideSize - 1, 1)) * size.width
        let y = center - CGFloat(samples[sampleIndex]) * center
        if pointIndex == 0 {
          path.move(to: CGPoint(x: x, y: y))
        } else {
          path.addLine(to: CGPoint(x: x, y: y))
        }
      }
      context.stroke(path, with: .color(.blue), lineWidth: 1)
    }
    .background(Color.black.opacity(0.06))
  }
}

private struct FrequencyResponseGraph: View {
  let channels: [[FrequencyResponsePoint]]

  var body: some View {
    Canvas { context, size in
      drawGrid(context: context, size: size)
      let colors: [Color] = [.blue, .orange]
      for (channelIndex, response) in channels.prefix(2).enumerated() {
        var path = Path()
        for (index, point) in response.enumerated() {
          let x = log10(point.frequency / 20) / log10(20_000.0 / 20.0) * size.width
          let clamped = min(max(point.smoothedDecibels, -48), 24)
          let y = CGFloat((24 - clamped) / 72) * size.height
          if index == 0 {
            path.move(to: CGPoint(x: x, y: y))
          } else {
            path.addLine(to: CGPoint(x: x, y: y))
          }
        }
        context.stroke(path, with: .color(colors[channelIndex]), lineWidth: 2)
      }
    }
    .overlay(alignment: .topLeading) {
      Text("20 Hz – 20 kHz  •  1/12 oct  •  1 kHz = 0 dB")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(8)
    }
  }

  private func drawGrid(context: GraphicsContext, size: CGSize) {
    var path = Path()
    for fraction in stride(from: 0.0, through: 1.0, by: 0.25) {
      let y = size.height * fraction
      path.move(to: CGPoint(x: 0, y: y))
      path.addLine(to: CGPoint(x: size.width, y: y))
    }
    for frequency in [20.0, 100, 1_000, 10_000, 20_000] {
      let x = log10(frequency / 20) / log10(20_000.0 / 20.0) * size.width
      path.move(to: CGPoint(x: x, y: 0))
      path.addLine(to: CGPoint(x: x, y: size.height))
    }
    context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
  }
}

#Preview {
  AnalyzeView(
    recordingFileStore: RecordingFileStore.shared,
    userDefaults: .standard,
    audioIOController: AudioIOController()
  )
}
