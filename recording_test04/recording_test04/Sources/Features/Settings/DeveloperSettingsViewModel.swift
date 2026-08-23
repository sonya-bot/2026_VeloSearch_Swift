import Foundation
import Observation

@Observable
@MainActor
final class DeveloperSettingsViewModel {
  private(set) var devCSVFiles: [URL] = []
  private let recordingFileStore: RecordingFileStoring

  init(recordingFileStore: RecordingFileStoring) {
    self.recordingFileStore = recordingFileStore
  }

  func loadDevCSVFiles() {
    do {
      try recordingFileStore.prepareStorage()
      devCSVFiles = recordingFileStore.allDevCSVFiles()
    } catch {
      devCSVFiles = []
      AppLogger.storage.error("Dev CSV一覧の取得に失敗しました: \(error.localizedDescription)")
    }
  }

}
