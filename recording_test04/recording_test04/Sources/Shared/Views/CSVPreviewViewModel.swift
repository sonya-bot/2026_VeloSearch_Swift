import Foundation
import Observation

struct CSVDataRow: Identifiable {
  let id = UUID()
  let columns: [String]
}

enum CSVPreviewLoadState: Equatable {
  case idle, loading, loaded, missing, empty, failed
}

enum MeasurementCSVKind: String, CaseIterable, Identifiable {
  case timeSeries = "時系列"
  case localization = "推論イベント"
  var id: Self { self }
}

@MainActor
@Observable
final class CSVPreviewViewModel {
  private(set) var loadState: CSVPreviewLoadState = .idle
  private(set) var headers: [String] = []
  private(set) var rows: [CSVDataRow] = []
  private(set) var selectedKind: MeasurementCSVKind
  private(set) var canSwitchCSV: Bool
  private let timeSeriesURL: URL
  private let localizationURL: URL
  private let recordingFileStore: RecordingFileStoring

  var csvURL: URL { selectedKind == .timeSeries ? timeSeriesURL : localizationURL }

  init(csvURL: URL, recordingFileStore: RecordingFileStoring) {
    self.recordingFileStore = recordingFileStore
    let originalStem = csvURL.deletingPathExtension().lastPathComponent
    let isLocalization = originalStem.hasPrefix("Localization_")
    let isDevelopment = originalStem.hasPrefix("Dev_")
    let baseName: String
    if isLocalization {
      baseName = String(originalStem.dropFirst("Localization_".count))
    } else if isDevelopment {
      baseName = String(originalStem.dropFirst("Dev_".count))
    } else {
      baseName = originalStem
    }
    let directory = csvURL.deletingLastPathComponent()
    localizationURL = directory.appendingPathComponent("Localization_\(baseName).csv")
    let standardURL = directory.appendingPathComponent("\(baseName).csv")
    let legacyURL = directory.appendingPathComponent("Dev_\(baseName).csv")
    if isLocalization {
      timeSeriesURL =
        !recordingFileStore.fileExists(at: standardURL)
          && recordingFileStore.fileExists(at: legacyURL) ? legacyURL : standardURL
    } else {
      timeSeriesURL = csvURL
    }
    selectedKind = isLocalization ? .localization : .timeSeries
    canSwitchCSV =
      isLocalization || isDevelopment || baseName.hasPrefix("Detecting_")
      || recordingFileStore.fileExists(at: localizationURL)
  }

  func select(_ kind: MeasurementCSVKind) {
    selectedKind = kind
    load()
  }

  func load() {
    loadState = .loading
    headers = []
    rows = []
    guard recordingFileStore.fileExists(at: csvURL) else {
      loadState = .missing
      return
    }
    do {
      let parsedRows = try CSVCodec.parse(recordingFileStore.csvContents(at: csvURL))
      guard let firstRow = parsedRows.first else {
        loadState = .empty
        return
      }
      headers = firstRow
      if headers.contains("localization_state") { canSwitchCSV = true }
      rows = parsedRows.dropFirst().map { CSVDataRow(columns: $0) }
      loadState = rows.isEmpty ? .empty : .loaded
    } catch {
      loadState = .failed
      AppLogger.storage.error("CSVの読み込みに失敗しました: \(error.localizedDescription)")
    }
  }
}
