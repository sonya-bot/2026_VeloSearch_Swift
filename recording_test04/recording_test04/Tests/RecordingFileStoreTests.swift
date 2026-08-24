import Foundation
import Testing

@testable import recording_test04

struct RecordingFileStoreTests {
  @Test
  func prepareStorageCreatesDefaultDirectory() throws {
    let context = try makeTestContext()

    try context.store.prepareStorage()

    #expect(context.fileManager.fileExists(atPath: context.store.defaultDirectory.path))
    #expect(
      context.userDefaults.string(forKey: RecordingFileStore.selectedSceneKey)
        == RecordingFileStore.defaultSceneName
    )
  }

  @Test
  func recordingURLUsesExistingDailySequence() throws {
    let context = try makeTestContext()
    try context.store.prepareStorage()
    let firstRecording = context.store.defaultDirectory
      .appendingPathComponent("Recording_20260821_01.wav")
    try Data().write(to: firstRecording)

    let date = try #require(
      Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 8, day: 21)
      )
    )
    let recording = try context.store.makeRecordingURL(prefix: "Recording", date: date)

    #expect(recording.baseName == "Recording_20260821_02")
    #expect(recording.url.lastPathComponent == "Recording_20260821_02.wav")
  }

  @Test
  func renamingSelectedSceneUpdatesPersistedSelection() throws {
    let context = try makeTestContext()
    try context.store.prepareStorage()
    let scene = try context.store.createScene(named: "Road")
    context.userDefaults.set("Road", forKey: RecordingFileStore.selectedSceneKey)

    let renamedScene = try context.store.renameScene(at: scene, to: "Bridge")

    #expect(renamedScene.lastPathComponent == "Bridge")
    #expect(
      context.userDefaults.string(forKey: RecordingFileStore.selectedSceneKey) == "Bridge"
    )
  }

  @Test
  func deletingRecordingRemovesExistingCompanionFiles() throws {
    let context = try makeTestContext()
    try context.store.prepareStorage()
    let baseName = "Detecting_20260821_01"
    let audioURL = context.store.defaultDirectory.appendingPathComponent("\(baseName).wav")
    let csvURL = context.store.defaultDirectory.appendingPathComponent("\(baseName).csv")
    let devCSVURL = context.store.defaultDirectory.appendingPathComponent("Dev_\(baseName).csv")
    for fileURL in [audioURL, csvURL, devCSVURL] {
      try Data().write(to: fileURL)
    }

    try context.store.deleteRecording(at: audioURL)

    #expect(!context.fileManager.fileExists(atPath: audioURL.path))
    #expect(!context.fileManager.fileExists(atPath: csvURL.path))
    #expect(!context.fileManager.fileExists(atPath: devCSVURL.path))
  }

  @Test
  func renamingRecordingMovesAudioAndCompanionCSVFilesTogether() throws {
    let context = try makeTestContext()
    try context.store.prepareStorage()
    let oldBaseName = "Recording_20260821_01"
    let newBaseName = "Bridge_Angle090_Take1"
    let audioURL = context.store.defaultDirectory.appendingPathComponent("\(oldBaseName).wav")
    let csvURL = context.store.defaultDirectory.appendingPathComponent("\(oldBaseName).csv")
    let devCSVURL = context.store.defaultDirectory.appendingPathComponent("Dev_\(oldBaseName).csv")
    for fileURL in [audioURL, csvURL, devCSVURL] {
      try Data().write(to: fileURL)
    }

    let renamedURL = try context.store.renameRecording(at: audioURL, to: newBaseName)

    #expect(renamedURL.lastPathComponent == "\(newBaseName).wav")
    #expect(context.fileManager.fileExists(atPath: renamedURL.path))
    #expect(
      context.fileManager.fileExists(
        atPath: context.store.defaultDirectory.appendingPathComponent("\(newBaseName).csv").path
      )
    )
    #expect(
      context.fileManager.fileExists(
        atPath: context.store.defaultDirectory.appendingPathComponent("Dev_\(newBaseName).csv").path
      )
    )
    #expect(!context.fileManager.fileExists(atPath: audioURL.path))
  }

  @Test
  func shareableFilesPreserveExistingTypeRules() throws {
    let context = try makeTestContext()
    try context.store.prepareStorage()
    let files = [
      "Detecting_20260821_01.wav",
      "Detecting_20260821_01.csv",
      "Dev_Detecting_20260821_01.csv",
      "Localization_Detecting_20260821_01.csv",
    ]
    for fileName in files {
      try Data().write(to: context.store.defaultDirectory.appendingPathComponent(fileName))
    }

    let standardCSVFiles = context.store.shareableFiles(
      in: context.store.defaultDirectory,
      type: .csv
    )
    let devCSVFiles = context.store.shareableFiles(
      in: context.store.defaultDirectory,
      type: .devCSV
    )

    #expect(
      standardCSVFiles.map(\.lastPathComponent) == [
        "Detecting_20260821_01.csv",
        "Localization_Detecting_20260821_01.csv",
      ])
    #expect(devCSVFiles.map(\.lastPathComponent) == ["Dev_Detecting_20260821_01.csv"])
  }

  @Test
  func devCSVFilesAreSortedByModificationDateDescending() throws {
    let context = try makeTestContext()
    try context.store.prepareStorage()
    let olderURL = context.store.defaultDirectory.appendingPathComponent("Dev_Older.csv")
    let newerURL = context.store.defaultDirectory.appendingPathComponent("Dev_Newer.csv")
    try Data().write(to: olderURL)
    try Data().write(to: newerURL)
    try context.fileManager.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1)],
      ofItemAtPath: olderURL.path
    )
    try context.fileManager.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 2)],
      ofItemAtPath: newerURL.path
    )

    let files = context.store.allDevCSVFiles()

    #expect(files.map(\.lastPathComponent) == ["Dev_Newer.csv", "Dev_Older.csv"])
  }

  @Test
  func fileExistsReturnsTrueOnlyForFiles() throws {
    let context = try makeTestContext()
    try context.store.prepareStorage()
    let csvURL = context.store.defaultDirectory.appendingPathComponent("Recording.csv")
    try Data().write(to: csvURL)

    #expect(context.store.fileExists(at: csvURL))
    #expect(!context.store.fileExists(at: context.store.defaultDirectory))
    #expect(
      !context.store.fileExists(
        at: context.store.defaultDirectory.appendingPathComponent("Missing.csv")
      )
    )
  }

  private func makeTestContext() throws -> TestContext {
    let fileManager = FileManager.default
    let rootDirectory = fileManager.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

    let suiteName = "RecordingFileStoreTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    userDefaults.removePersistentDomain(forName: suiteName)
    let store = RecordingFileStore(
      fileManager: fileManager,
      userDefaults: userDefaults,
      documentsDirectory: rootDirectory
    )

    return TestContext(
      fileManager: fileManager,
      userDefaults: userDefaults,
      store: store
    )
  }
}

private struct TestContext {
  let fileManager: FileManager
  let userDefaults: UserDefaults
  let store: RecordingFileStore
}
