import AudioToolbox
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct DetectionView_Previews: PreviewProvider {
  static var previews: some View {
    DetectionView(
      recordingFileStore: RecordingFileStore.shared,
      audioIOController: AudioIOController(),
      locationService: LocationService()
    )
  }
}

// MARK: -2 DetentingsView(画面UI)
struct DetectionView: View {
  @State private var detection: DetectionController
  private let recordingFileStore: RecordingFileStoring
  @ObservedObject private var audioIOController: AudioIOController
  @State private var locationManager: LocationService
  @AppStorage("warningSoundID") private var selectedSoundID: Int = 1052
  @AppStorage("deviceOrientation") private var selectedOrientation: String = "横"
  @AppStorage("micSource") private var selectedMicSource: String = "背面"
  @AppStorage("showDebugOverlay") private var showDebugOverlay = false
  @AppStorage(RecordingFileStore.selectedSceneKey) private var selectedScene = RecordingFileStore
    .defaultSceneName
  @AppStorage("measurementDirectionTag") private var directionTag = MeasurementDirectionTag.none
  @AppStorage("selectedMonitoringSound") private var selectedTestSound = MonitoringSoundSource
    .sweep5Seconds

  init(
    recordingFileStore: RecordingFileStoring,
    audioIOController: AudioIOController,
    locationService: LocationService
  ) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
    _locationManager = State(initialValue: locationService)
    _detection = State(
      initialValue: DetectionController(
        recordingFileStore: recordingFileStore,
        audioIOController: audioIOController
      )
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color(UIColor.systemGroupedBackground).ignoresSafeArea()

        GeometryReader { geometry in
          let isLandscape = geometry.size.width > geometry.size.height

          if isLandscape {
            MeasurementLandscapeLayout { _ in
              VStack(spacing: 10) {
                detectionPanel(isLandscape: true)
                actionButtons
              }
            } trailingContent: { _ in
              VStack(spacing: 8) {
                AudioRouteStatusButton(audioIOController: audioIOController)
                measurementSettings
                detectionDetails
              }
            }
          } else {
            VStack(spacing: 10) {
              AudioRouteStatusButton(audioIOController: audioIOController)
              measurementSettings
              detectionPanel(isLandscape: false)
                .frame(maxHeight: .infinity)
              actionButtons
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
          }
        }
      }
      .navigationTitle("Detectings")
      .navigationBarTitleDisplayMode(.inline)
      // 連続したDetect期間につき、アラート音は最初の1回だけ再生する。
      .onChange(of: detection.warningTriggerID) { oldValue, newValue in
        if newValue > oldValue {
          AudioServicesPlaySystemSound(SystemSoundID(selectedSoundID))
        }
      }
      .onAppear {
        if !selectedTestSound.isBundled {
          selectedTestSound = .sweep5Seconds
        }
      }
      .onDisappear { detection.stopTestSound() }
    }
  }

  // MARK: - UI Components
  private var statusView: some View {
    let statusText: String
    if let angle = detection.currentAIAngle,
      detection.state == .detect || detection.state == .uncertain
    {
      statusText = "\(detection.state.title) (\(angle)°)"
    } else {
      statusText = detection.state.title
    }
    return HStack(spacing: 8) {
      Circle()
        .fill(detection.state.themeColor)
        .frame(width: 10, height: 10)
      Text(statusText)
        .font(.title2.bold())
        .minimumScaleFactor(0.6)
    }
    .foregroundStyle(detection.state.themeColor)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(detection.state.themeColor.opacity(0.12), in: Capsule())
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Status: \(statusText)")
  }

  private func detectionPanel(isLandscape: Bool) -> some View {
    VStack(spacing: 0) {
      statusView
      Spacer(minLength: 0)
      RadarView(state: detection.state, aiAngle: detection.currentAIAngle)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 220, maxHeight: 220)
        .overlay(alignment: .bottomTrailing) {
          if showDebugOverlay {
            debugOverlay(isLandscape: isLandscape)
          }
        }
      Spacer(minLength: 0)
      if !isLandscape {
        HStack {
          Text(formatElapsedTime(detection.elapsedTime))
          Spacer()
          Text(currentDecibelText)
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 12)

        directionProbabilityBars
          .frame(height: 92)
          .padding(.horizontal, 12)
          .padding(.bottom, 8)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
    }
  }

  private func debugOverlay(isLandscape: Bool) -> some View {
    let angleText = detection.currentAIAngle.map(String.init) ?? "--"
    let probabilityText =
      detection.currentAIAngle == nil
      ? "--"
      : String(Int(detection.currentAIProbability))
    return VStack(alignment: .leading, spacing: 4) {
      Text("AI: \(angleText)deg / \(probabilityText)%")
      Text("Update: \(Int(detection.debugLastUpdateMs))ms")
      Text(
        "Skipped: Extract \(detection.debugFeatureSkipCount) / AI \(detection.debugPredictionSkipCount)"
      )
    }
    .font(.system(size: 12, weight: .medium, design: .monospaced))
    .foregroundStyle(.primary)
    .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemBackground).opacity(0.82)))
    .overlay(
      RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
    )
    .offset(x: isLandscape ? -50 : 80, y: 20)
  }

  private var measurementSettings: some View {
    HStack(spacing: 8) {
      MeasurementDestinationPicker(
        recordingFileStore: recordingFileStore,
        selection: $selectedScene,
        isDisabled: detection.isRecording
      )
      MeasurementDirectionPicker(selection: $directionTag, isDisabled: detection.isRecording)
    }
  }

  private var controlButton: some View {
    MeasurementControlButton(
      idleTitle: "Start",
      activeTitle: "Stop",
      isActive: detection.isRecording,
      tint: .red,
      isDisabled: false
    ) {
      withAnimation(.spring()) {
        if detection.isRecording {
          detection.stopDetecting()
        } else {
          detection.startDetecting(
            locationManager: locationManager, orientation: selectedOrientation,
            micSource: selectedMicSource, directionTag: directionTag)
        }
      }
    }
  }

  private var testButton: some View {
    MeasurementControlButton(
      idleTitle: "Test",
      activeTitle: "Stop Test",
      isActive: detection.isTestSoundPlaying,
      tint: .orange,
      isDisabled: false
    ) {
      detection.toggleTestSound(selectedTestSound)
    }
  }

  private var actionButtons: some View {
    HStack(spacing: 0) {
      controlButton
        .frame(maxWidth: .infinity)
      testButton
        .frame(maxWidth: .infinity)
    }
    .frame(height: 80)
  }

  private var detectionDetails: some View {
    VStack(spacing: 8) {
      HStack {
        Text("Detection probability")
          .font(.headline)
        Spacer()
        Text(formatElapsedTime(detection.elapsedTime))
          .monospacedDigit()
        Text(currentDecibelText)
          .monospacedDigit()
      }
      .font(.caption)

      directionProbabilityBars
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private var directionProbabilityBars: some View {
    GeometryReader { geometry in
      HStack(alignment: .bottom, spacing: 6) {
        ForEach(0..<8, id: \.self) { index in
          let probability =
            detection.currentDirectionProbabilities.indices.contains(index)
            ? detection.currentDirectionProbabilities[index] : 0
          VStack(spacing: 3) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.blue)
              .frame(
                height: max(
                  2,
                  (geometry.size.height - 22)
                    * min(max(CGFloat(probability), 0), 1)
                )
              )
            Text("\(index * 45)°")
              .font(.caption2)
              .minimumScaleFactor(0.7)
          }
          .frame(maxWidth: .infinity)
        }
      }
    }
  }

  private var currentDecibelText: String {
    let decibels = detection.currentDecibel <= -160 ? 0 : detection.currentDecibel
    return String(format: "%.1f dB", decibels)
  }

  private func formatElapsedTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }
}
