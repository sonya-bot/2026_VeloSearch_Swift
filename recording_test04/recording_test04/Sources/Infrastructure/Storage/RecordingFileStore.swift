import Foundation

/// Sceneフォルダ、Default、録音ファイルの命名規則を一元管理する。
final class RecordingFileStore: RecordingFileStoring {
  static let shared = RecordingFileStore()

  static let defaultSceneName = "Default"
  static let selectedSceneKey = "selectedSceneFolderName"

  private let fileManager: FileManager
  private let userDefaults: UserDefaults
  private let documentsDirectoryURL: URL

  init(
    fileManager: FileManager = .default,
    userDefaults: UserDefaults = .standard,
    documentsDirectory: URL? = nil
  ) {
    self.fileManager = fileManager
    self.userDefaults = userDefaults
    self.documentsDirectoryURL =
      documentsDirectory
      ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  var documentsDirectory: URL {
    documentsDirectoryURL
  }

  var defaultDirectory: URL {
    documentsDirectory.appendingPathComponent(Self.defaultSceneName, isDirectory: true)
  }

  func prepareStorage() throws {
    try fileManager.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
    // 移行できなかった元ファイルは残し、録音機能自体は継続できるようにする。
    try? migrateRootFilesToDefault()

    let selected: String
    if let persistedSelection = userDefaults.string(forKey: Self.selectedSceneKey) {
      selected = persistedSelection
    } else {
      selected = Self.defaultSceneName
      userDefaults.set(Self.defaultSceneName, forKey: Self.selectedSceneKey)
    }
    if selected != Self.defaultSceneName && !sceneExists(named: selected) {
      userDefaults.set(Self.defaultSceneName, forKey: Self.selectedSceneKey)
    }
  }

  func sceneDirectories() -> [URL] {
    (try? fileManager.contentsOfDirectory(
      at: documentsDirectory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ))?.filter { url in
      guard url.lastPathComponent != Self.defaultSceneName else { return false }
      return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }.sorted {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    } ?? []
  }

  func recordings(in directory: URL) -> [URL] {
    (try? fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ))?.filter {
      let name = $0.deletingPathExtension().lastPathComponent
      return $0.pathExtension.lowercased() == "wav" && !name.contains("_IR_CH")
    }
    .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
  }

  func selectedDirectory() throws -> URL {
    try prepareStorage()
    let selectedName =
      userDefaults.string(forKey: Self.selectedSceneKey)
      ?? Self.defaultSceneName
    if selectedName == Self.defaultSceneName {
      return defaultDirectory
    }

    let directory = documentsDirectory.appendingPathComponent(selectedName, isDirectory: true)
    guard sceneExists(named: selectedName) else {
      userDefaults.set(Self.defaultSceneName, forKey: Self.selectedSceneKey)
      return defaultDirectory
    }
    return directory
  }

  func makeRecordingURL(prefix: String, date: Date = Date()) throws -> (baseName: String, url: URL)
  {
    // 録音開始時に保存先と連番を確定し、処理中の設定変更から切り離す。
    let directory = try selectedDirectory()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let dateString = formatter.string(from: date)
    let sequence = nextSequenceNumber(prefix: prefix, dateString: dateString, in: directory)
    let baseName = "\(prefix)_\(dateString)_\(String(format: "%02d", sequence))"
    return (baseName, directory.appendingPathComponent("\(baseName).wav"))
  }

  func nextSequenceNumber(prefix: String, dateString: String, in directory: URL) -> Int {
    let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
    let escapedDate = NSRegularExpression.escapedPattern(for: dateString)
    let pattern = "^\(escapedPrefix)_\(escapedDate)_([0-9]+)\\.wav$"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return 1 }

    let maximum =
      recordings(in: directory).compactMap { url -> Int? in
        let name = url.lastPathComponent
        let range = NSRange(name.startIndex..., in: name)
        guard let match = regex.firstMatch(in: name, range: range),
          let numberRange = Range(match.range(at: 1), in: name)
        else { return nil }
        return Int(name[numberRange])
      }.max() ?? 0

    return maximum + 1
  }

  @discardableResult
  func createScene(named rawName: String) throws -> URL {
    let name = try validatedSceneName(rawName)
    guard !sceneExists(named: name) else { throw RecordingFileStoreError.duplicateSceneName }
    let url = documentsDirectory.appendingPathComponent(name, isDirectory: true)
    try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }

  @discardableResult
  func renameScene(at sceneURL: URL, to rawName: String) throws -> URL {
    let name = try validatedSceneName(rawName)
    guard sceneURL.lastPathComponent != Self.defaultSceneName else {
      throw RecordingFileStoreError.reservedSceneName
    }

    let oldName = sceneURL.lastPathComponent
    if oldName == name { return sceneURL }
    guard !sceneExists(named: name) else { throw RecordingFileStoreError.duplicateSceneName }

    let destination = documentsDirectory.appendingPathComponent(name, isDirectory: true)
    try fileManager.moveItem(at: sceneURL, to: destination)
    if userDefaults.string(forKey: Self.selectedSceneKey) == oldName {
      userDefaults.set(name, forKey: Self.selectedSceneKey)
    }
    return destination
  }

  func deleteScene(at sceneURL: URL) throws {
    guard sceneURL.lastPathComponent != Self.defaultSceneName else {
      throw RecordingFileStoreError.reservedSceneName
    }
    guard fileManager.fileExists(atPath: sceneURL.path) else {
      throw RecordingFileStoreError.missingScene
    }

    let deletedName = sceneURL.lastPathComponent
    try fileManager.removeItem(at: sceneURL)
    if userDefaults.string(forKey: Self.selectedSceneKey) == deletedName {
      userDefaults.set(Self.defaultSceneName, forKey: Self.selectedSceneKey)
    }
  }

  func deleteRecording(at audioURL: URL) throws {
    let baseName = audioURL.deletingPathExtension().lastPathComponent
    let folder = audioURL.deletingLastPathComponent()
    let files = try fileManager.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    let relatedURLs = files.filter { url in
      let stem = url.deletingPathExtension().lastPathComponent
      return stem == baseName || stem == "Dev_\(baseName)" || stem == "Localization_\(baseName)"
        || stem.hasPrefix("\(baseName)_IR_CH")
    }

    for url in relatedURLs where fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  @discardableResult
  func renameRecording(at audioURL: URL, to rawBaseName: String) throws -> URL {
    let baseName = rawBaseName
    let oldBaseName = audioURL.deletingPathExtension().lastPathComponent
    guard baseName != oldBaseName else { return audioURL }

    let directory = audioURL.deletingLastPathComponent()
    let renamedAudioURL = directory.appendingPathComponent(baseName).appendingPathExtension(
      audioURL.pathExtension)
    let relatedNames = [
      ("\(oldBaseName).csv", "\(baseName).csv"),
      ("Dev_\(oldBaseName).csv", "Dev_\(baseName).csv"),
      ("Localization_\(oldBaseName).csv", "Localization_\(baseName).csv"),
    ]
    let companions = relatedNames.map { oldName, newName in
      (directory.appendingPathComponent(oldName), directory.appendingPathComponent(newName))
    }.filter { fileExists(at: $0.0) }
    let moves = [(audioURL, renamedAudioURL)] + companions
    guard !moves.contains(where: { fileManager.fileExists(atPath: $0.1.path) }) else {
      throw RecordingFileStoreError.duplicateRecordingName
    }
    var completedMoves: [(URL, URL)] = []
    do {
      for (source, destination) in moves {
        try fileManager.moveItem(at: source, to: destination)
        completedMoves.append((source, destination))
      }
    } catch {
      for (source, destination) in completedMoves.reversed() {
        do { try fileManager.moveItem(at: destination, to: source) } catch {
          AppLogger.storage.error("録音名変更の復旧に失敗しました: \(error.localizedDescription)")
        }
      }
      throw error
    }
    return renamedAudioURL
  }

  func shareableFiles(in sceneURL: URL, type: SceneShareType) -> [URL] {
    let files =
      (try? fileManager.contentsOfDirectory(
        at: sceneURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []

    return files.filter { url in
      let ext = url.pathExtension.lowercased()
      let isDevCSV = ext == "csv" && url.lastPathComponent.hasPrefix("Dev_")
      switch type {
      case .wav: return ext == "wav"
      case .csv: return ext == "csv" && !isDevCSV
      case .devCSV: return isDevCSV
      case .all: return ext == "wav" || ext == "csv" || ext == "json"
      }
    }.sorted {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
  }

  func createShareArchive(sceneURL: URL, type: SceneShareType) throws -> URL {
    let files = shareableFiles(in: sceneURL, type: type)
    guard !files.isEmpty else { throw RecordingFileStoreError.noShareableFiles }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let archiveName =
      "\(sceneURL.lastPathComponent)_\(type.archiveLabel)_\(formatter.string(from: Date())).zip"
    let archiveURL = fileManager.temporaryDirectory.appendingPathComponent(archiveName)
    if fileManager.fileExists(atPath: archiveURL.path) {
      try fileManager.removeItem(at: archiveURL)
    }
    try StoredZIPWriter.write(files: files, to: archiveURL)
    return archiveURL
  }

  func diagnosticCSVFiles() -> [URL] {
    let directories = [defaultDirectory] + sceneDirectories()
    return directories.flatMap { directory in
      ((try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )) ?? []).filter {
        guard $0.pathExtension.lowercased() == "csv" else { return false }
        let name = $0.lastPathComponent
        if name.hasPrefix("Dev_") { return true }
        if name.hasPrefix("Localization_") {
          let baseName = String(name.dropFirst("Localization_".count))
          return !fileExists(at: directory.appendingPathComponent(baseName))
            && !fileExists(at: directory.appendingPathComponent("Dev_\(baseName)"))
        }
        let companion = directory.appendingPathComponent("Localization_\(name)")
        if name.hasPrefix("Detecting_") || fileExists(at: companion) { return true }
        guard let contents = try? csvContents(at: $0),
          let headers = try? CSVCodec.parse(contents).first
        else {
          return false
        }
        return headers.contains("localization_state")
      }
    }.sorted { lhs, rhs in
      let lhsDate = try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      let rhsDate = try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
    }
  }

  func writeCSV(_ contents: String, to url: URL) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  func csvContents(at url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
  }

  func fileExists(at url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && !isDirectory.boolValue
  }

  func directoryExists(at url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private func sceneExists(named name: String) -> Bool {
    sceneDirectories().contains {
      $0.lastPathComponent.compare(name, options: [.caseInsensitive, .diacriticInsensitive])
        == .orderedSame
    }
  }

  private func validatedSceneName(_ rawName: String) throws -> String {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name != ".", name != ".." else {
      throw RecordingFileStoreError.invalidSceneName
    }
    guard
      name.compare(Self.defaultSceneName, options: [.caseInsensitive, .diacriticInsensitive])
        != .orderedSame
    else {
      throw RecordingFileStoreError.reservedSceneName
    }

    let invalidCharacters = CharacterSet(charactersIn: "/:\\").union(.newlines).union(
      .controlCharacters)
    guard name.rangeOfCharacter(from: invalidCharacters) == nil else {
      throw RecordingFileStoreError.invalidSceneName
    }
    return name
  }

  private func migrateRootFilesToDefault() throws {
    let rootFiles = try fileManager.contentsOfDirectory(
      at: documentsDirectory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ).filter { url in
      let ext = url.pathExtension.lowercased()
      return ext == "wav" || ext == "csv" || ext == "json"
    }

    // 同じ録音のWAV・CSV・Dev CSVを一組として移行し、衝突時も同じ連番を保つ。
    let groups = Dictionary(grouping: rootFiles) { url -> String in
      let stem = url.deletingPathExtension().lastPathComponent
      let prefix = companionPrefix(for: url)
      return String(stem.dropFirst(prefix.count))
    }

    for (baseName, files) in groups {
      var destinationBaseName = baseName
      let hasCollision = files.contains { file in
        let name = "\(companionPrefix(for: file))\(destinationBaseName).\(file.pathExtension)"
        return fileManager.fileExists(atPath: defaultDirectory.appendingPathComponent(name).path)
      }

      if hasCollision, let components = recordingNameComponents(baseName) {
        var next = nextSequenceNumber(
          prefix: components.prefix,
          dateString: components.date,
          in: defaultDirectory
        )
        destinationBaseName =
          "\(components.prefix)_\(components.date)_\(String(format: "%02d", next))"
        while destinationGroupExists(destinationBaseName, files: files, in: defaultDirectory) {
          next += 1
          destinationBaseName =
            "\(components.prefix)_\(components.date)_\(String(format: "%02d", next))"
        }
      } else if hasCollision {
        destinationBaseName = uniqueBaseName(baseName, in: defaultDirectory)
      }

      for source in files {
        let devPrefix = companionPrefix(for: source)
        let destination = defaultDirectory.appendingPathComponent(
          "\(devPrefix)\(destinationBaseName).\(source.pathExtension)"
        )
        guard !fileManager.fileExists(atPath: destination.path) else { continue }
        try fileManager.moveItem(at: source, to: destination)
      }
    }
  }

  private func companionPrefix(for url: URL) -> String {
    if url.lastPathComponent.hasPrefix("Dev_") { return "Dev_" }
    if url.lastPathComponent.hasPrefix("Localization_") { return "Localization_" }
    return ""
  }

  private func recordingNameComponents(_ baseName: String) -> (prefix: String, date: String)? {
    let pattern = "^(.+)_([0-9]{8})_[0-9]+$"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(baseName.startIndex..., in: baseName)
    guard let match = regex.firstMatch(in: baseName, range: range),
      let prefixRange = Range(match.range(at: 1), in: baseName),
      let dateRange = Range(match.range(at: 2), in: baseName)
    else { return nil }
    return (String(baseName[prefixRange]), String(baseName[dateRange]))
  }

  private func uniqueBaseName(_ baseName: String, in directory: URL) -> String {
    var suffix = 2
    var candidate = "\(baseName)_\(suffix)"
    while fileManager.fileExists(atPath: directory.appendingPathComponent("\(candidate).wav").path)
      || fileManager.fileExists(atPath: directory.appendingPathComponent("\(candidate).csv").path)
      || fileManager.fileExists(
        atPath: directory.appendingPathComponent("Dev_\(candidate).csv").path)
      || fileManager.fileExists(
        atPath: directory.appendingPathComponent("Localization_\(candidate).csv").path)
    {
      suffix += 1
      candidate = "\(baseName)_\(suffix)"
    }
    return candidate
  }

  private func destinationGroupExists(_ baseName: String, files: [URL], in directory: URL) -> Bool {
    files.contains { file in
      let devPrefix = companionPrefix(for: file)
      let destination = directory.appendingPathComponent(
        "\(devPrefix)\(baseName).\(file.pathExtension)"
      )
      return fileManager.fileExists(atPath: destination.path)
    }
  }
}

/// 外部ライブラリに依存せず、共有用の無圧縮ZIPを生成する。
