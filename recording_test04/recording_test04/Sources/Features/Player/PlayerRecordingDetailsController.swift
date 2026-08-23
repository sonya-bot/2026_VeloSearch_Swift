import Foundation

struct CSVRecord {
  let time: Double
  let speed: String
}

struct RecordingDetails {
  var note = ""
  var experimenter = ""
  var weather = ""
  var temperature = ""
  var humidity = ""
  var scene = ""
}

/// プレイヤー画面の付帯情報と関連CSVの永続化を担当する。
final class PlayerRecordingDetailsController {
  private let recordingFileStore: RecordingFileStoring
  private let userDefaults: UserDefaults

  init(recordingFileStore: RecordingFileStoring, userDefaults: UserDefaults) {
    self.recordingFileStore = recordingFileStore
    self.userDefaults = userDefaults
  }

  func details(for audioURL: URL) -> RecordingDetails {
    let fileName = audioURL.lastPathComponent
    return RecordingDetails(
      note: userDefaults.string(forKey: "\(fileName)_note")
        ?? userDefaults.string(forKey: fileName) ?? "",
      experimenter: userDefaults.string(forKey: "\(fileName)_experimenter") ?? "",
      weather: userDefaults.string(forKey: "\(fileName)_weather") ?? "",
      temperature: userDefaults.string(forKey: "\(fileName)_temperature") ?? "",
      humidity: userDefaults.string(forKey: "\(fileName)_humidity") ?? "",
      scene: userDefaults.string(forKey: "\(fileName)_scene") ?? ""
    )
  }

  func save(
    details: RecordingDetails,
    for audioURL: URL,
    renamedTo newBaseName: String
  ) -> URL {
    let oldFileName = audioURL.lastPathComponent
    var destinationURL = audioURL
    let oldBaseName = audioURL.deletingPathExtension().lastPathComponent

    if newBaseName != oldBaseName, !newBaseName.isEmpty {
      do {
        destinationURL = try recordingFileStore.renameRecording(
          at: audioURL,
          to: newBaseName
        )
      } catch {
        AppLogger.storage.error("録音名の変更に失敗しました: \(error.localizedDescription)")
      }
    }

    if oldFileName != destinationURL.lastPathComponent {
      removeDetails(for: oldFileName)
    }
    persist(details, for: destinationURL.lastPathComponent)
    return destinationURL
  }

  func speedRecords(for audioURL: URL) -> [CSVRecord] {
    let csvURL = audioURL.deletingPathExtension().appendingPathExtension("csv")
    do {
      let csvString = try recordingFileStore.csvContents(at: csvURL)
      return csvString.components(separatedBy: .newlines).dropFirst().compactMap { line in
        let columns = line.components(separatedBy: ",")
        guard columns.count >= 2, let time = Double(columns[0]) else { return nil }
        return CSVRecord(time: time, speed: columns[1])
      }
    } catch {
      AppLogger.storage.notice("対応する速度CSVを読み込めませんでした")
      return []
    }
  }

  private func persist(_ details: RecordingDetails, for fileName: String) {
    userDefaults.set(details.note, forKey: "\(fileName)_note")
    userDefaults.set(details.experimenter, forKey: "\(fileName)_experimenter")
    userDefaults.set(details.weather, forKey: "\(fileName)_weather")
    userDefaults.set(details.temperature, forKey: "\(fileName)_temperature")
    userDefaults.set(details.humidity, forKey: "\(fileName)_humidity")
    userDefaults.set(details.scene, forKey: "\(fileName)_scene")
  }

  private func removeDetails(for fileName: String) {
    userDefaults.removeObject(forKey: "\(fileName)_note")
    userDefaults.removeObject(forKey: fileName)
    userDefaults.removeObject(forKey: "\(fileName)_experimenter")
    userDefaults.removeObject(forKey: "\(fileName)_weather")
    userDefaults.removeObject(forKey: "\(fileName)_temperature")
    userDefaults.removeObject(forKey: "\(fileName)_humidity")
    userDefaults.removeObject(forKey: "\(fileName)_scene")
  }
}
