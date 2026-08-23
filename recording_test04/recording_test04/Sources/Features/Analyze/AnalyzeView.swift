import SwiftUI

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
    audioIOController: AudioIOController,
    resultWriter: AnalyzeResultWriting
  ) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
    _controller = StateObject(
      wrappedValue: AnalyzeController(
        recordingFileStore: recordingFileStore,
        audioIOController: audioIOController,
        resultWriter: resultWriter
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
            MeasurementLandscapeLayout { _ in
              VStack(spacing: 8) {
                analyzeStatusPanel
                Spacer(minLength: 0)
                measurementButton
                Spacer(minLength: 0)
              }
            } trailingContent: { _ in
              VStack(spacing: 8) {
                AudioRouteStatusButton(audioIOController: audioIOController)
                measurementSettings(isCompact: true)
                waveformSection
                  .frame(height: waveformDisplayCount >= 2 ? 62 : 38)
                responseGraph
              }
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
            .padding(.horizontal, MeasurementLayoutMetrics.horizontalPadding)
            .padding(.bottom, 8)
          }
        }
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
