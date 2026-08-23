import Foundation
import Observation

struct CSVDataRow: Identifiable {
  let id = UUID()
  let columns: [String]
}

@MainActor
@Observable
final class CSVPreviewViewModel {
  private(set) var headers: [String] = []
  private(set) var rows: [CSVDataRow] = []

  private let csvURL: URL
  private let recordingFileStore: RecordingFileStoring

  init(csvURL: URL, recordingFileStore: RecordingFileStoring) {
    self.csvURL = csvURL
    self.recordingFileStore = recordingFileStore
  }

  func load() {
    do {
      let contents = try recordingFileStore.csvContents(at: csvURL)
      let lines = contents.components(separatedBy: .newlines).filter { !$0.isEmpty }
      guard let firstLine = lines.first else { return }

      headers = firstLine.components(separatedBy: ",")
      rows = lines.dropFirst().map { line in
        CSVDataRow(columns: line.components(separatedBy: ","))
      }
    } catch {
      AppLogger.storage.error("CSVの読み込みに失敗しました: \(error.localizedDescription)")
    }
  }
}
