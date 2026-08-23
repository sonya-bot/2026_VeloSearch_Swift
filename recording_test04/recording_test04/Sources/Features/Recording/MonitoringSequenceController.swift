import Foundation
import Observation

@Observable
@MainActor
final class MonitoringSequenceController {
  private let audioMonitor: AudioMonitoringController
  private var repeatTransitionTask: Task<Void, Never>?

  private(set) var currentRepeat = 0
  private(set) var isRepeatSequenceActive = false
  private(set) var countdownValue: Int?

  init(audioMonitor: AudioMonitoringController) {
    self.audioMonitor = audioMonitor
  }

  func toggleSequence(
    repeatCount: Int,
    orientation: String,
    micSource: String,
    directionTag: MeasurementDirectionTag
  ) {
    if isRepeatSequenceActive {
      stopSequence()
    } else {
      startSequence(
        repeatCount: repeatCount,
        orientation: orientation,
        micSource: micSource,
        directionTag: directionTag
      )
    }
  }

  func cancelPendingTransition() {
    repeatTransitionTask?.cancel()
  }

  private func startSequence(
    repeatCount: Int,
    orientation: String,
    micSource: String,
    directionTag: MeasurementDirectionTag
  ) {
    currentRepeat = 1
    isRepeatSequenceActive = true
    startCurrentRepeat(
      repeatCount: repeatCount,
      orientation: orientation,
      micSource: micSource,
      directionTag: directionTag
    )
  }

  private func stopSequence() {
    isRepeatSequenceActive = false
    repeatTransitionTask?.cancel()
    countdownValue = nil
    audioMonitor.stopRecording()
  }

  private func startCurrentRepeat(
    repeatCount: Int,
    orientation: String,
    micSource: String,
    directionTag: MeasurementDirectionTag
  ) {
    repeatTransitionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for seconds in stride(from: 3, through: 1, by: -1) {
        countdownValue = seconds
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, isRepeatSequenceActive else { return }
      }
      countdownValue = nil
      audioMonitor.startRecording(
        orientation: orientation,
        micSource: micSource,
        prefix: "Monitoring",
        directionTag: directionTag == .none ? nil : directionTag.rawValue
      ) { [weak self] in
        Task { @MainActor [weak self] in
          self?.recordingDidFinish(
            repeatCount: repeatCount,
            orientation: orientation,
            micSource: micSource,
            directionTag: directionTag
          )
        }
      }
      if !audioMonitor.isRecording {
        isRepeatSequenceActive = false
      }
    }
  }

  private func recordingDidFinish(
    repeatCount: Int,
    orientation: String,
    micSource: String,
    directionTag: MeasurementDirectionTag
  ) {
    guard isRepeatSequenceActive else { return }
    guard currentRepeat < repeatCount else {
      isRepeatSequenceActive = false
      return
    }

    repeatTransitionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled, isRepeatSequenceActive else { return }
      currentRepeat += 1
      startCurrentRepeat(
        repeatCount: repeatCount,
        orientation: orientation,
        micSource: micSource,
        directionTag: directionTag
      )
    }
  }
}
