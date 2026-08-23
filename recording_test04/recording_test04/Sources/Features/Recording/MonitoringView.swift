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
  @State private var sequenceController: MonitoringSequenceController
  @Environment(\.verticalSizeClass) var verticalSizeClass

  @AppStorage("deviceOrientation") private var selectedOrientation: String = "横"
  @AppStorage("micSource") private var selectedMicSource: String = "背面"
  @AppStorage(RecordingFileStore.selectedSceneKey) private var selectedScene = RecordingFileStore
    .defaultSceneName
  @AppStorage("measurementDirectionTag") private var directionTag: MeasurementDirectionTag = .none
  @AppStorage("monitoringRepeatCount") private var repeatCount = 1

  init(
    recordingFileStore: RecordingFileStoring,
    userDefaults: UserDefaults,
    audioIOController: AudioIOController
  ) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
    let audioMonitor = AudioMonitoringController(
      recordingFileStore: recordingFileStore,
      userDefaults: userDefaults,
      audioIOController: audioIOController
    )
    _audioMonitor = State(initialValue: audioMonitor)
    _sequenceController = State(
      initialValue: MonitoringSequenceController(audioMonitor: audioMonitor)
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        // 背景色
        Color(UIColor.systemGroupedBackground).ignoresSafeArea()

        if verticalSizeClass == .compact {
          // 【横画面レイアウト】
          MeasurementLandscapeLayout { _ in
            VStack(spacing: 10) {
              timeDisplay
              monitoringStatus
              Spacer(minLength: 0)
              recordButton
              Spacer(minLength: 0)
            }
          } trailingContent: { availableSize in
            let meterWidth = min(340, max(150, availableSize.width * 0.36))
            VStack(spacing: 8) {
              AudioRouteStatusButton(audioIOController: audioIOController)
              measurementSettings(isCompact: true)
              horizontalStereoMeters(width: meterWidth, height: 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
          }
        } else {
          // 【縦画面レイアウト】
          GeometryReader { geometry in
            // 固定余白を削り、余った縦方向の領域をステレオメーターの高さに回す。
            let meterHeight = min(210, max(120, geometry.size.height * 0.24))

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
              recordButton
            }
            .padding(.top, 4)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      .navigationTitle("Monitorings")
      .navigationBarTitleDisplayMode(.inline)
      .onDisappear {
        sequenceController.cancelPendingTransition()
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
    guard sequenceController.isRepeatSequenceActive else { return audioMonitor.measurementStatus }
    if let countdownValue = sequenceController.countdownValue {
      return "開始まで \(countdownValue) · \(sequenceController.currentRepeat) / \(repeatCount)"
    }
    return
      "\(audioMonitor.measurementStatus) · \(sequenceController.currentRepeat) / \(repeatCount)"
  }

  @ViewBuilder
  private func measurementSettings(isCompact: Bool) -> some View {
    if isCompact {
      HStack(spacing: 6) {
        MeasurementDestinationPicker(
          recordingFileStore: recordingFileStore,
          selection: $selectedScene,
          isDisabled: sequenceController.isRepeatSequenceActive
        )
        MeasurementDirectionPicker(
          selection: $directionTag,
          isDisabled: sequenceController.isRepeatSequenceActive
        )
        repeatStepper
      }
    } else {
      VStack(spacing: 8) {
        MeasurementDestinationPicker(
          recordingFileStore: recordingFileStore,
          selection: $selectedScene,
          isDisabled: sequenceController.isRepeatSequenceActive
        )
        HStack(spacing: 8) {
          MeasurementDirectionPicker(
            selection: $directionTag,
            isDisabled: sequenceController.isRepeatSequenceActive
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
    .disabled(sequenceController.isRepeatSequenceActive)
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
      isActive: sequenceController.isRepeatSequenceActive,
      tint: .red,
      isDisabled: !sequenceController.isRepeatSequenceActive
        && audioIOController.configurationIssue(allowsPlayback: true) != nil
    ) {
      sequenceController.toggleSequence(
        repeatCount: repeatCount,
        orientation: selectedOrientation,
        micSource: selectedMicSource,
        directionTag: directionTag
      )
    }
  }

  private var estimatedDurationSeconds: Int {
    audioMonitor.estimatedMonitoringDurationSeconds(repeatCount: repeatCount)
  }

  private func formatElapsedTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
    return String(format: "%02d:%02d.%02d", minutes, seconds, ms)
  }
}
