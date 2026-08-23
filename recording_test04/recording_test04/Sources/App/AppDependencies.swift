import Foundation

@MainActor
struct AppDependencies {
  let recordingFileStore: RecordingFileStoring
  let userDefaults: UserDefaults
  let notificationCenter: NotificationCenter
  let audioIOController: AudioIOController

  static let live = AppDependencies(
    recordingFileStore: RecordingFileStore.shared,
    userDefaults: .standard,
    notificationCenter: .default,
    audioIOController: AudioIOController()
  )
}
