import AVFoundation
import Combine
import Foundation

@MainActor
final class AnalyzeController: ObservableObject {
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
  private let resultWriter: AnalyzeResultWriting
  private let service = ESSMeasurementService()
  private let analyzer = ESSAnalyzer()
  private var executionTask: Task<Void, Never>?

  init(
    recordingFileStore: RecordingFileStoring,
    audioIOController: AudioIOController,
    resultWriter: AnalyzeResultWriting
  ) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
    self.resultWriter = resultWriter
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
      audioIOController.lockConfiguration()
      defer { audioIOController.unlockConfiguration() }
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
          try resultWriter.write(
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

}
