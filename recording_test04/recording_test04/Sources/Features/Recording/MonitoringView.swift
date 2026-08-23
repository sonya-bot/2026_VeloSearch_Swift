import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct MonitoringView_Previews: PreviewProvider {
  static var previews: some View {
    MonitoringView(
      recordingFileStore: RecordingFileStore.shared,
      userDefaults: .standard,
      audioIOController: AudioIOController()
    )
  }
}

// MARK: - 1. AudioMonitoringController (録音ロジック)
// Monitoring画面もRecordings画面と同じ録音クラスを使う。
typealias AudioMonitoringController = AudioRecordingController

// MARK: - 2. MonitoringView (UI)
struct MonitoringView: View {
  private let recordingFileStore: RecordingFileStoring
  @ObservedObject private var audioIOController: AudioIOController
  @State private var audioMonitor: AudioMonitoringController
  @Environment(\.verticalSizeClass) var verticalSizeClass

  @AppStorage("deviceOrientation") private var selectedOrientation: String = "横"
  @AppStorage("micSource") private var selectedMicSource: String = "背面"
  @AppStorage(RecordingFileStore.selectedSceneKey) private var selectedScene = RecordingFileStore
    .defaultSceneName
  @AppStorage("measurementDirectionTag") private var directionTag: MeasurementDirectionTag = .none
  @AppStorage("monitoringRepeatCount") private var repeatCount = 1
  @State private var currentRepeat = 0
  @State private var isRepeatSequenceActive = false
  @State private var repeatTransitionTask: Task<Void, Never>?
  @State private var countdownValue: Int?

  init(
    recordingFileStore: RecordingFileStoring,
    userDefaults: UserDefaults,
    audioIOController: AudioIOController
  ) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
    _audioMonitor = State(
      initialValue: AudioMonitoringController(
        recordingFileStore: recordingFileStore,
        userDefaults: userDefaults,
        audioIOController: audioIOController
      )
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        // 背景色
        Color(UIColor.systemGroupedBackground).ignoresSafeArea()

        if verticalSizeClass == .compact {
          // 【横画面レイアウト】
          GeometryReader { geometry in
            let meterWidth = min(340, max(150, geometry.size.width * 0.36))

            HStack(spacing: 16) {
              VStack(spacing: 10) {
                timeDisplay
                monitoringStatus
                Spacer(minLength: 0)
                recordButton
                Spacer(minLength: 0)
              }
              .frame(width: (geometry.size.width - 16) / 3)

              VStack(spacing: 8) {
                AudioRouteStatusButton(
                  audioIOController: audioIOController,
                  displayMode: .compact
                )
                measurementSettings(isCompact: true)
                horizontalStereoMeters(width: meterWidth, height: 24)
                  .frame(maxWidth: .infinity, maxHeight: .infinity)
                  .background(Color(uiColor: .secondarySystemGroupedBackground))
                  .clipShape(RoundedRectangle(cornerRadius: 14))
              }
              .frame(width: (geometry.size.width - 16) * 2 / 3)
            }
            .frame(maxHeight: .infinity)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
        } else {
          // 【縦画面レイアウト】
          GeometryReader { geometry in
            // 固定余白を削り、余った縦方向の領域をステレオメーターの高さに回す。
            let meterHeight = min(220, max(180, geometry.size.height * 0.25))

            VStack(spacing: 10) {
              AudioRouteStatusButton(audioIOController: audioIOController)
              measurementSettings(isCompact: false)
              VStack(spacing: 8) {
                timeDisplay
                monitoringStatus
                verticalStereoMeters(height: meterHeight)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(Color(uiColor: .secondarySystemGroupedBackground))
              .clipShape(RoundedRectangle(cornerRadius: 16))
              Spacer(minLength: 4)
              recordButton
            }
            .padding(.top, 4)
            .padding(.horizontal)
            .padding(.bottom, 72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      .navigationTitle("Monitorings")
      .navigationBarTitleDisplayMode(.inline)
      .onDisappear {
        repeatTransitionTask?.cancel()
      }
    }
  }

  // MARK: - 4. Component
  // 時間表示
  private var timeDisplay: some View {
    Text(formatElapsedTime(audioMonitor.elapsedTime))
      .font(.system(size: 48, weight: .thin))
      .monospacedDigit()
  }

  // 録音状態の表示
  private var monitoringStatus: some View {
    Text(repeatStatus)
      .font(.headline)
      .foregroundColor(audioMonitor.isRecording ? .red : .secondary)
      .padding(.vertical, 6)
      .padding(.horizontal, 16)
      .background(Capsule().fill(Color.primary.opacity(0.1)))
  }

  private var repeatStatus: String {
    guard isRepeatSequenceActive else { return audioMonitor.measurementStatus }
    if let countdownValue { return "開始まで \(countdownValue) · \(currentRepeat) / \(repeatCount)" }
    return "\(audioMonitor.measurementStatus) · \(currentRepeat) / \(repeatCount)"
  }

  @ViewBuilder
  private func measurementSettings(isCompact: Bool) -> some View {
    if isCompact {
      HStack(spacing: 6) {
        MeasurementDestinationPicker(
          recordingFileStore: recordingFileStore,
          selection: $selectedScene,
          isDisabled: isRepeatSequenceActive
        )
        MeasurementDirectionPicker(
          selection: $directionTag,
          isDisabled: isRepeatSequenceActive
        )
        repeatStepper
      }
    } else {
      VStack(spacing: 8) {
        MeasurementDestinationPicker(
          recordingFileStore: recordingFileStore,
          selection: $selectedScene,
          isDisabled: isRepeatSequenceActive
        )
        HStack(spacing: 8) {
          MeasurementDirectionPicker(
            selection: $directionTag,
            isDisabled: isRepeatSequenceActive
          )
          repeatStepper
        }
        Text("所要時間 約 \(estimatedDurationSeconds) 秒")
          .font(.caption)
          .foregroundStyle(.secondary)
        if let issue = audioIOController.configurationIssue(allowsPlayback: true) {
          Text(issue)
            .font(.caption2)
            .foregroundStyle(.red)
        }
      }
    }
  }

  private var repeatStepper: some View {
    Stepper(value: $repeatCount, in: 1...99) {
      Text("Repeat \(repeatCount)")
        .font(.subheadline)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .disabled(isRepeatSequenceActive)
    .padding(.horizontal, 10)
    .frame(height: 48)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  // ステレオメーター部分(縦画面)
  private func verticalStereoMeters(height: CGFloat) -> some View {
    HStack(spacing: 50) {
      VStack {
        VerticaldBMeter(
          level: audioMonitor.leftLevel, label: "L", font: .system(.caption), height: height)
        Text("\(Int(audioMonitor.leftDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
      if audioMonitor.activeInputChannelCount >= 2 {
        VStack {
          VerticaldBMeter(
            level: audioMonitor.rightLevel, label: "R", font: .system(.caption), height: height)
          Text("\(Int(audioMonitor.rightDecibel)) dB")
            .font(.system(.title3))
            .monospacedDigit()
            .frame(width: 80)
        }
      }
    }
  }

  // ステレオメーター部分(横画面)
  private func horizontalStereoMeters(width: CGFloat, height: CGFloat) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 15) {
        HorizontaldBMeter(
          level: audioMonitor.leftLevel,
          label: "L",
          width: width,
          height: height,
          font: .system(.caption)
        )
        Text("\(Int(audioMonitor.leftDecibel)) dB")
          .font(.system(.subheadline))
          .monospacedDigit()
          .frame(width: 64, alignment: .leading)
      }
      if audioMonitor.activeInputChannelCount >= 2 {
        HStack(spacing: 15) {
          HorizontaldBMeter(
            level: audioMonitor.rightLevel,
            label: "R",
            width: width,
            height: height,
            font: .system(.caption)
          )
          Text("\(Int(audioMonitor.rightDecibel)) dB")
            .font(.system(.subheadline))
            .monospacedDigit()
            .frame(width: 64, alignment: .leading)
        }
      }
    }
  }

  // 録音ボタン
  private var recordButton: some View {
    MeasurementControlButton(
      idleTitle: "Start",
      activeTitle: "Stop",
      isActive: isRepeatSequenceActive,
      tint: .red,
      isDisabled: !isRepeatSequenceActive
        && audioIOController.configurationIssue(allowsPlayback: true) != nil
    ) {
      if isRepeatSequenceActive {
        isRepeatSequenceActive = false
        repeatTransitionTask?.cancel()
        countdownValue = nil
        audioMonitor.stopRecording()
      } else {
        startRepeatSequence()
      }
    }
  }

  private func startRepeatSequence() {
    currentRepeat = 1
    isRepeatSequenceActive = true
    startCurrentRepeat()
  }

  private func startCurrentRepeat() {
    repeatTransitionTask = Task { @MainActor in
      for seconds in stride(from: 3, through: 1, by: -1) {
        countdownValue = seconds
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, isRepeatSequenceActive else { return }
      }
      countdownValue = nil
      audioMonitor.startRecording(
        orientation: selectedOrientation,
        micSource: selectedMicSource,
        prefix: "Monitoring",
        directionTag: directionTag == .none ? nil : directionTag.rawValue
      ) {
        Task { @MainActor in
          guard isRepeatSequenceActive else { return }
          guard currentRepeat < repeatCount else {
            isRepeatSequenceActive = false
            return
          }
          repeatTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, isRepeatSequenceActive else { return }
            currentRepeat += 1
            startCurrentRepeat()
          }
        }
      }
      if !audioMonitor.isRecording {
        isRepeatSequenceActive = false
      }
    }
  }

  private var estimatedDurationSeconds: Int {
    let soundRawValue =
      UserDefaults.standard.string(forKey: "selectedMonitoringSound")
      ?? MonitoringSoundSource.sweep5Seconds.rawValue
    let sound = MonitoringSoundSource(rawValue: soundRawValue) ?? .sweep5Seconds
    let duration =
      Bundle.main.url(forResource: sound.fileName, withExtension: "wav")
      .flatMap { try? AVAudioPlayer(contentsOf: $0).duration } ?? 0
    return Int(ceil(duration)) * repeatCount + 3 * repeatCount + 3 * max(repeatCount - 1, 0)
  }

  private func formatElapsedTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
    return String(format: "%02d:%02d.%02d", minutes, seconds, ms)
  }
}
