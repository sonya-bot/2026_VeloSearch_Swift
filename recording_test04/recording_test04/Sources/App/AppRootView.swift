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
      Tab("Detectings", systemImage: "scope", value: 0) {
        DetectionView(
          recordingFileStore: dependencies.recordingFileStore,
          audioIOController: dependencies.audioIOController,
          locationService: dependencies.locationService
        )
      }

      Tab(
        viewModel.isMonitoringEnabled ? "Monitorings" : "Recordings",
        systemImage: viewModel.isMonitoringEnabled ? "headphones" : "mic.fill",
        value: 1
      ) {
        recordingTab
      }

      Tab("Analyze", systemImage: "chart.xyaxis.line", value: 2) {
        AnalyzeView(
          recordingFileStore: dependencies.recordingFileStore,
          userDefaults: dependencies.userDefaults,
          audioIOController: dependencies.audioIOController,
          resultWriter: dependencies.analyzeResultWriter
        )
      }

      Tab("Collections", systemImage: "square.stack.fill", value: 3) {
        CollectionsView(
          recordingFileStore: dependencies.recordingFileStore,
          userDefaults: dependencies.userDefaults
        )
      }

      Tab("Settings", systemImage: "gearshape", value: 4) {
        SettingsView(
          recordingFileStore: dependencies.recordingFileStore,
          audioIOController: dependencies.audioIOController,
          audioPreviewController: dependencies.audioPreviewController
        )
      }

    }
    .tabViewStyle(.sidebarAdaptable)
    .task {
      await dependencies.audioIOController.applyStoredSelection()
    }
  }

  @ViewBuilder
  private var recordingTab: some View {
    if viewModel.isMonitoringEnabled {
      MonitoringView(
        recordingFileStore: dependencies.recordingFileStore,
        userDefaults: dependencies.userDefaults,
        audioIOController: dependencies.audioIOController
      )
    } else {
      RecordingView(
        recordingFileStore: dependencies.recordingFileStore,
        userDefaults: dependencies.userDefaults,
        audioIOController: dependencies.audioIOController
      )
    }
  }
}
