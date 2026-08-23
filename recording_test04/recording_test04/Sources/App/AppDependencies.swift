import Foundation

@MainActor
struct AppDependencies {
  let recordingFileStore: RecordingFileStoring
  let userDefaults: UserDefaults
  let notificationCenter: NotificationCenter
  let audioIOController: AudioIOController
  let locationService: LocationService
  let audioPreviewController: AudioPreviewController
  let analyzeResultWriter: AnalyzeResultWriting

  static let live = AppDependencies(
    recordingFileStore: RecordingFileStore.shared,
    userDefaults: .standard,
    notificationCenter: .default,
    audioIOController: AudioIOController(),
    locationService: LocationService(),
    audioPreviewController: AudioPreviewController(),
    analyzeResultWriter: AnalyzeResultWriter()
  )
}
