import Combine
import Foundation

@MainActor
final class SceneRecordingsViewModel: ObservableObject {
  @Published private(set) var items: [URL] = []
  @Published var errorMessage: String?

  private let sceneURL: URL
  private let recordingFileStore: RecordingFileStoring

  init(sceneURL: URL, recordingFileStore: RecordingFileStoring) {
    self.sceneURL = sceneURL
    self.recordingFileStore = recordingFileStore
  }

  func refresh() {
    items = recordingFileStore.recordings(in: sceneURL)
  }

  func deleteRecording(at audioURL: URL) -> Bool {
    do {
      try recordingFileStore.deleteRecording(at: audioURL)
      refresh()
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }
}
