import Foundation

protocol RecordingFileStoring: AnyObject {
  var documentsDirectory: URL { get }
  var defaultDirectory: URL { get }

  func prepareStorage() throws
  func sceneDirectories() -> [URL]
  func recordings(in directory: URL) -> [URL]
  func selectedDirectory() throws -> URL
  func makeRecordingURL(prefix: String, date: Date) throws -> (baseName: String, url: URL)
  func nextSequenceNumber(prefix: String, dateString: String, in directory: URL) -> Int
  @discardableResult func createScene(named rawName: String) throws -> URL
  @discardableResult func renameScene(at sceneURL: URL, to rawName: String) throws -> URL
  func deleteScene(at sceneURL: URL) throws
  func deleteRecording(at audioURL: URL) throws
  @discardableResult func renameRecording(at audioURL: URL, to rawBaseName: String) throws -> URL
  func shareableFiles(in sceneURL: URL, type: SceneShareType) -> [URL]
  func createShareArchive(sceneURL: URL, type: SceneShareType) throws -> URL
  func allDevCSVFiles() -> [URL]
  func csvContents(at url: URL) throws -> String
  func directoryExists(at url: URL) -> Bool
}

extension RecordingFileStoring {
  func makeRecordingURL(prefix: String) throws -> (baseName: String, url: URL) {
    try makeRecordingURL(prefix: prefix, date: Date())
  }
}

enum RecordingFileStoreError: LocalizedError {
  case invalidSceneName
  case reservedSceneName
  case duplicateSceneName
  case missingScene
  case noShareableFiles
  case archiveTooLarge

  var errorDescription: String? {
    switch self {
    case .invalidSceneName:
      return [
        "Scene名を入力してください。",
        "使用できない文字が含まれていないか確認してください。",
      ].joined()
    case .reservedSceneName:
      return "DefaultはScene名として使用できません。"
    case .duplicateSceneName:
      return "同じ名前のSceneが既に存在します。"
    case .missingScene:
      return "Sceneが見つかりません。"
    case .noShareableFiles:
      return "共有できるファイルがありません。"
    case .archiveTooLarge:
      return "共有するファイルがZIPの上限を超えています。"
        + "対象を分けて共有してください。"
    }
  }
}

enum SceneShareType: String, CaseIterable, Identifiable {
  case wav = "WAV"
  case csv = "CSV"
  case devCSV = "Dev CSV"
  case all = "すべて"

  var id: Self { self }

  var archiveLabel: String {
    switch self {
    case .wav: return "WAV"
    case .csv: return "CSV"
    case .devCSV: return "DevCSV"
    case .all: return "All"
    }
  }
}
