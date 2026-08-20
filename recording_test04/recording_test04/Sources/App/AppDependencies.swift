import Foundation

struct AppDependencies {
  let recordingFileStore: RecordingFileStoring
  let userDefaults: UserDefaults
  let notificationCenter: NotificationCenter

  static let live = AppDependencies(
    recordingFileStore: RecordingFileStore.shared,
    userDefaults: .standard,
    notificationCenter: .default
  )
}
