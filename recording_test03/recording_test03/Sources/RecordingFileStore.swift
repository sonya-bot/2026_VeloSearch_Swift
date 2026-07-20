import Foundation

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
      return "Scene名を入力してください。使用できない文字が含まれていないか確認してください。"
    case .reservedSceneName:
      return "DefaultはScene名として使用できません。"
    case .duplicateSceneName:
      return "同じ名前のSceneが既に存在します。"
    case .missingScene:
      return "Sceneが見つかりません。"
    case .noShareableFiles:
      return "共有できるファイルがありません。"
    case .archiveTooLarge:
      return "共有するファイルがZIPの上限を超えています。対象を分けて共有してください。"
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

/// Sceneフォルダ、Default、録音ファイルの命名規則を一元管理する。
final class RecordingFileStore {
  static let shared = RecordingFileStore()

  static let defaultSceneName = "Default"
  static let selectedSceneKey = "selectedSceneFolderName"

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  var documentsDirectory: URL {
    fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  var defaultDirectory: URL {
    documentsDirectory.appendingPathComponent(Self.defaultSceneName, isDirectory: true)
  }

  func prepareStorage() throws {
    try fileManager.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
    // 移行できなかった元ファイルは残し、録音機能自体は継続できるようにする。
    try? migrateRootFilesToDefault()

    let selected = UserDefaults.standard.string(forKey: Self.selectedSceneKey)
      ?? Self.defaultSceneName
    if selected != Self.defaultSceneName && !sceneExists(named: selected) {
      UserDefaults.standard.set(Self.defaultSceneName, forKey: Self.selectedSceneKey)
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
    ))?.filter { $0.pathExtension.lowercased() == "wav" }
      .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
  }

  func selectedDirectory() throws -> URL {
    try prepareStorage()
    let selectedName = UserDefaults.standard.string(forKey: Self.selectedSceneKey)
      ?? Self.defaultSceneName
    if selectedName == Self.defaultSceneName {
      return defaultDirectory
    }

    let directory = documentsDirectory.appendingPathComponent(selectedName, isDirectory: true)
    guard sceneExists(named: selectedName) else {
      UserDefaults.standard.set(Self.defaultSceneName, forKey: Self.selectedSceneKey)
      return defaultDirectory
    }
    return directory
  }

  func makeRecordingURL(prefix: String, date: Date = Date()) throws -> (baseName: String, url: URL) {
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

    let maximum = recordings(in: directory).compactMap { url -> Int? in
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
    if UserDefaults.standard.string(forKey: Self.selectedSceneKey) == oldName {
      UserDefaults.standard.set(name, forKey: Self.selectedSceneKey)
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
    if UserDefaults.standard.string(forKey: Self.selectedSceneKey) == deletedName {
      UserDefaults.standard.set(Self.defaultSceneName, forKey: Self.selectedSceneKey)
    }
  }

  func deleteRecording(at audioURL: URL) throws {
    let baseName = audioURL.deletingPathExtension().lastPathComponent
    let folder = audioURL.deletingLastPathComponent()
    let relatedURLs = [
      audioURL,
      folder.appendingPathComponent("\(baseName).csv"),
      folder.appendingPathComponent("Dev_\(baseName).csv"),
    ]

    for url in relatedURLs where fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  func shareableFiles(in sceneURL: URL, type: SceneShareType) -> [URL] {
    let files = (try? fileManager.contentsOfDirectory(
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
      case .all: return ext == "wav" || ext == "csv"
      }
    }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
  }

  func createShareArchive(sceneURL: URL, type: SceneShareType) throws -> URL {
    let files = shareableFiles(in: sceneURL, type: type)
    guard !files.isEmpty else { throw RecordingFileStoreError.noShareableFiles }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let archiveName = "\(sceneURL.lastPathComponent)_\(type.archiveLabel)_\(formatter.string(from: Date())).zip"
    let archiveURL = fileManager.temporaryDirectory.appendingPathComponent(archiveName)
    if fileManager.fileExists(atPath: archiveURL.path) {
      try fileManager.removeItem(at: archiveURL)
    }
    try StoredZIPWriter.write(files: files, to: archiveURL)
    return archiveURL
  }

  func allDevCSVFiles() -> [URL] {
    let directories = [defaultDirectory] + sceneDirectories()
    return directories.flatMap { directory in
      ((try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []).filter {
        $0.pathExtension.lowercased() == "csv" && $0.lastPathComponent.hasPrefix("Dev_")
      }
    }.sorted { $0.lastPathComponent > $1.lastPathComponent }
  }

  private func sceneExists(named name: String) -> Bool {
    sceneDirectories().contains {
      $0.lastPathComponent.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
  }

  private func validatedSceneName(_ rawName: String) throws -> String {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name != ".", name != ".." else {
      throw RecordingFileStoreError.invalidSceneName
    }
    guard name.compare(Self.defaultSceneName, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame else {
      throw RecordingFileStoreError.reservedSceneName
    }

    let invalidCharacters = CharacterSet(charactersIn: "/:\\").union(.newlines).union(.controlCharacters)
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
      return ext == "wav" || ext == "csv"
    }

    // 同じ録音のWAV・CSV・Dev CSVを一組として移行し、衝突時も同じ連番を保つ。
    let groups = Dictionary(grouping: rootFiles) { url -> String in
      let stem = url.deletingPathExtension().lastPathComponent
      return stem.hasPrefix("Dev_") ? String(stem.dropFirst(4)) : stem
    }

    for (baseName, files) in groups {
      var destinationBaseName = baseName
      let hasCollision = files.contains { file in
        let name = file.lastPathComponent.hasPrefix("Dev_")
          ? "Dev_\(destinationBaseName).\(file.pathExtension)"
          : "\(destinationBaseName).\(file.pathExtension)"
        return fileManager.fileExists(atPath: defaultDirectory.appendingPathComponent(name).path)
      }

      if hasCollision, let components = recordingNameComponents(baseName) {
        var next = nextSequenceNumber(
          prefix: components.prefix,
          dateString: components.date,
          in: defaultDirectory
        )
        destinationBaseName = "\(components.prefix)_\(components.date)_\(String(format: "%02d", next))"
        while destinationGroupExists(destinationBaseName, files: files, in: defaultDirectory) {
          next += 1
          destinationBaseName = "\(components.prefix)_\(components.date)_\(String(format: "%02d", next))"
        }
      } else if hasCollision {
        destinationBaseName = uniqueBaseName(baseName, in: defaultDirectory)
      }

      for source in files {
        let devPrefix = source.lastPathComponent.hasPrefix("Dev_") ? "Dev_" : ""
        let destination = defaultDirectory.appendingPathComponent(
          "\(devPrefix)\(destinationBaseName).\(source.pathExtension)"
        )
        guard !fileManager.fileExists(atPath: destination.path) else { continue }
        try fileManager.moveItem(at: source, to: destination)
      }
    }
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
    {
      suffix += 1
      candidate = "\(baseName)_\(suffix)"
    }
    return candidate
  }

  private func destinationGroupExists(_ baseName: String, files: [URL], in directory: URL) -> Bool {
    files.contains { file in
      let devPrefix = file.lastPathComponent.hasPrefix("Dev_") ? "Dev_" : ""
      let destination = directory.appendingPathComponent(
        "\(devPrefix)\(baseName).\(file.pathExtension)"
      )
      return fileManager.fileExists(atPath: destination.path)
    }
  }
}

/// 外部ライブラリに依存せず、共有用の無圧縮ZIPを生成する。
private enum StoredZIPWriter {
  private struct Entry {
    let nameData: Data
    let crc32: UInt32
    let size: UInt32
    let offset: UInt32
  }

  static func write(files: [URL], to destination: URL) throws {
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let output = try FileHandle(forWritingTo: destination)
    defer { try? output.close() }

    var currentOffset: UInt32 = 0
    var entries: [Entry] = []

    for file in files {
      let nameData = Data(file.lastPathComponent.utf8)
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
      guard fileSize <= UInt32.max, nameData.count <= UInt16.max else {
        throw RecordingFileStoreError.archiveTooLarge
      }
      let size = UInt32(fileSize)
      let checksum = try crc32(file)

      var header = Data()
      appendUInt32(0x04034b50, to: &header)
      appendUInt16(20, to: &header)
      appendUInt16(0x0800, to: &header) // UTF-8 file name
      appendUInt16(0, to: &header) // Stored (no compression)
      appendUInt16(0, to: &header)
      appendUInt16(0, to: &header)
      appendUInt32(checksum, to: &header)
      appendUInt32(size, to: &header)
      appendUInt32(size, to: &header)
      appendUInt16(UInt16(nameData.count), to: &header)
      appendUInt16(0, to: &header)
      header.append(nameData)
      try output.write(contentsOf: header)

      let input = try FileHandle(forReadingFrom: file)
      while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
        try output.write(contentsOf: chunk)
      }
      try input.close()

      entries.append(Entry(nameData: nameData, crc32: checksum, size: size, offset: currentOffset))
      let nextOffset = UInt64(currentOffset) + UInt64(header.count) + UInt64(size)
      guard nextOffset <= UInt32.max else { throw RecordingFileStoreError.archiveTooLarge }
      currentOffset = UInt32(nextOffset)
    }

    guard entries.count <= UInt16.max else { throw RecordingFileStoreError.archiveTooLarge }
    let centralDirectoryOffset = currentOffset
    var centralDirectory = Data()
    for entry in entries {
      appendUInt32(0x02014b50, to: &centralDirectory)
      appendUInt16(20, to: &centralDirectory)
      appendUInt16(20, to: &centralDirectory)
      appendUInt16(0x0800, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt32(entry.crc32, to: &centralDirectory)
      appendUInt32(entry.size, to: &centralDirectory)
      appendUInt32(entry.size, to: &centralDirectory)
      appendUInt16(UInt16(entry.nameData.count), to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt32(0, to: &centralDirectory)
      appendUInt32(entry.offset, to: &centralDirectory)
      centralDirectory.append(entry.nameData)
    }

    try output.write(contentsOf: centralDirectory)
    var footer = Data()
    appendUInt32(0x06054b50, to: &footer)
    appendUInt16(0, to: &footer)
    appendUInt16(0, to: &footer)
    appendUInt16(UInt16(entries.count), to: &footer)
    appendUInt16(UInt16(entries.count), to: &footer)
    appendUInt32(UInt32(centralDirectory.count), to: &footer)
    appendUInt32(centralDirectoryOffset, to: &footer)
    appendUInt16(0, to: &footer)
    try output.write(contentsOf: footer)
  }

  private static func crc32(_ file: URL) throws -> UInt32 {
    var crc: UInt32 = 0xffffffff
    let input = try FileHandle(forReadingFrom: file)
    while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
      for byte in chunk {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
          crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0)
        }
      }
    }
    try input.close()
    return crc ^ 0xffffffff
  }

  private static func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
  }

  private static func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 24) & 0xff))
  }
}
