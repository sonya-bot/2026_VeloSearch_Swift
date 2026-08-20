import SwiftUI

struct AppRootView: View {
  private let dependencies: AppDependencies
  @StateObject private var viewModel: AppRootViewModel

  init(dependencies: AppDependencies) {
    self.dependencies = dependencies
    _viewModel = StateObject(
      wrappedValue: AppRootViewModel(
        userDefaults: dependencies.userDefaults,
        notificationCenter: dependencies.notificationCenter
      )
    )
  }

  var body: some View {
    TabView(selection: $viewModel.selectedTab) {
      Tab("Detectings", systemImage: "waveform", value: 0) {
        DetectionView(recordingFileStore: dependencies.recordingFileStore)
      }

      Tab(
        viewModel.isMonitoringEnabled ? "Monitorings" : "Recordings",
        systemImage: viewModel.isMonitoringEnabled ? "headphones" : "mic.fill",
        value: 1
      ) {
        recordingTab
      }

      Tab("Collections", systemImage: "square.stack.fill", value: 2) {
        CollectionsView(
          recordingFileStore: dependencies.recordingFileStore,
          userDefaults: dependencies.userDefaults
        )
      }

      Tab("Settings", systemImage: "gearshape", value: 3) {
        SettingsView(recordingFileStore: dependencies.recordingFileStore)
      }
    }
    .tabViewStyle(.sidebarAdaptable)
  }

  @ViewBuilder
  private var recordingTab: some View {
    if viewModel.isMonitoringEnabled {
      MonitoringView(
        recordingFileStore: dependencies.recordingFileStore,
        userDefaults: dependencies.userDefaults
      )
    } else {
      RecordingView(
        recordingFileStore: dependencies.recordingFileStore,
        userDefaults: dependencies.userDefaults
      )
    }
  }
}
