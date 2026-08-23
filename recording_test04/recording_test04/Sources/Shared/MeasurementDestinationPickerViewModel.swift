import Combine
import Foundation

@MainActor
final class MeasurementDestinationPickerViewModel: ObservableObject {
  @Published private(set) var scenes: [String] = []
  private let recordingFileStore: RecordingFileStoring

  init(recordingFileStore: RecordingFileStoring) {
    self.recordingFileStore = recordingFileStore
  }

  func refreshedSelection(from selection: String) -> String {
    do {
      try recordingFileStore.prepareStorage()
      scenes = recordingFileStore.sceneDirectories().map(\.lastPathComponent)
      guard selection == RecordingFileStore.defaultSceneName || scenes.contains(selection) else {
        return RecordingFileStore.defaultSceneName
      }
      return selection
    } catch {
      scenes = []
      return RecordingFileStore.defaultSceneName
    }
  }
}
