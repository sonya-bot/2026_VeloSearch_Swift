import SwiftUI

struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView(
      recordingFileStore: RecordingFileStore.shared,
      audioIOController: AudioIOController(),
      audioPreviewController: AudioPreviewController(),
      modelSelection: AppDependencies.live.directionModelSelection,
      versionLabel: AppDependencies.live.measurementEnvironment.versionLabel
    )
  }
}

struct SettingsView: View {
  @Bindable private var modelSelection: DirectionModelSelectionController
  private let versionLabel: String
  private let recordingFileStore: RecordingFileStoring
  private let audioPreviewController: AudioPreviewController
  @ObservedObject private var audioIOController: AudioIOController
  @AppStorage(SettingsStorageKey.isNoiseFilterEnabled) private var isNoiseFilterEnabled = false
  @AppStorage(SettingsStorageKey.warningSoundID) private var selectedSoundID = 1052
  @AppStorage(SettingsStorageKey.isMonitoringEnabled) private var isMonitoringEnabled = false
  @AppStorage(SettingsStorageKey.selectedMonitoringSound) private var selectedTestSound =
    MonitoringSoundSource.sweep5Seconds
  @AppStorage(SettingsStorageKey.showDebugOverlay) private var showDebugOverlay = false

  init(
    recordingFileStore: RecordingFileStoring,
    audioIOController: AudioIOController,
    audioPreviewController: AudioPreviewController,
    modelSelection: DirectionModelSelectionController,
    versionLabel: String
  ) {
    self.modelSelection = modelSelection
    self.versionLabel = versionLabel
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
    self.audioPreviewController = audioPreviewController
  }

  var body: some View {
    NavigationStack {
      Form {
        generalSettingsSection
        recordingSettingsSection
        developerSettingsSection
        aboutSection
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .alert(
        "推論モデル",
        isPresented: Binding(
          get: { modelSelection.message != nil },
          set: { if !$0 { modelSelection.message = nil } }
        )
      ) {
        Button("OK") { modelSelection.message = nil }
      } message: {
        Text(modelSelection.message ?? "")
      }
    }
  }

  private var generalSettingsSection: some View {
    Section {
      NavigationLink {
        DirectionModelSelectionView(
          controller: modelSelection, audioIOController: audioIOController)
      } label: {
        SettingsNavigationRow(
          systemName: "brain", color: .purple, title: "推論モデル",
          value: modelSelection.selectedModelName ?? "利用不可"
        )
      }
      Toggle(isOn: $isNoiseFilterEnabled) {
        SettingsRowLabel(
          systemName: "waveform.badge.minus",
          color: .green,
          title: "Noise Filter"
        )
      }
      .tint(.green)

      NavigationLink(
        destination: AlertSoundSettingView(audioPreviewController: audioPreviewController)
      ) {
        SettingsNavigationRow(
          systemName: "bell.badge.fill",
          color: .red,
          title: "Alert Sound",
          value: SoundOption.available.first { $0.id == selectedSoundID }?.name ?? ""
        )
      }
    } header: {
      Text("General Settings")
    } footer: {
      Text("・録音時の環境ノイズを低減します(動作しません)\n・車両接近検知時の警告音を選択します")
        .font(.system(size: 12))
    }
  }

  private var recordingSettingsSection: some View {
    Section {
      NavigationLink(destination: AudioIOSettingsView(audioIOController: audioIOController)) {
        SettingsNavigationRow(
          systemName: "waveform.circle.fill",
          color: .blue,
          title: "Audio Input / Output",
          value: audioIOController.activeConfiguration.channelLabel
        )
      }

      NavigationLink(
        destination: TestSoundSelectionView(audioPreviewController: audioPreviewController)
      ) {
        SettingsNavigationRow(
          systemName: "speaker.wave.2.fill",
          color: .orange,
          title: "テスト音源",
          value: selectedTestSound.rawValue
        )
      }

      NavigationLink(destination: MonitoringSettingView()) {
        SettingsNavigationRow(
          systemName: "headphones",
          color: .pink,
          title: "モニタリング",
          value: isMonitoringEnabled ? "ON" : "OFF"
        )
      }
    } header: {
      Text("Recording Settings")
    }
  }

  private var developerSettingsSection: some View {
    Section {
      NavigationLink(
        destination: DeveloperSettingsView(recordingFileStore: recordingFileStore)
      ) {
        SettingsNavigationRow(
          systemName: "wrench.and.screwdriver.fill",
          color: .gray,
          title: "デベロッパ",
          value: showDebugOverlay ? "ON" : "OFF"
        )
      }
    }
  }

  private var aboutSection: some View {
    Section {
      HStack {
        Text("Version")
          .font(.system(size: 16))
        Spacer()
        Text(versionLabel)
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("About")
    }
  }
}
