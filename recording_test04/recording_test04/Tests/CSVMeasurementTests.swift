import Foundation
import Testing

@testable import recording_test04

struct CSVMeasurementTests {
  @Test
  func csvRoundTripsQuotedMultilineFieldsAndTrailingEmptyColumn() throws {
    let fields = [
      "one,two", "\"quoted\"", "line1\r\nline2", "plain\nnewline", "plain\rcarriage", "日本語", "",
    ]
    let serialized = CSVCodec.row(fields)
    #expect(try CSVCodec.parse("first,second\r\n" + serialized + "\r\n").last == fields)
  }

  @Test
  func malformedQuoteIsRejected() {
    #expect(throws: CSVCodec.ParseError.self) { try CSVCodec.parse("one,\"unfinished") }
    #expect(throws: CSVCodec.ParseError.self) { try CSVCodec.parse("\"value\"tail") }
  }

  @Test
  func timingSeparatesCoreMLCallAndMainActorDelay() {
    let timing = LocalizationTiming(
      beepDetected: 100, audioReady: 101.5, featureStarted: 101.6, featureCompleted: 101.8,
      predictionStarted: 101.9, predictionCompleted: 102, uiUpdated: 102.025
    )
    #expect(timing.durationFields == ["1500.000", "200.000", "100.000", "25.000", "2025.000"])
    #expect(
      timing.boundaryFields(relativeTo: 100) == [
        "1.500", "1.600", "1.800", "1.900", "2.000", "2.025",
      ])
    #expect(LocalizationTiming(beepDetected: 100).durationFields == ["", "", "", "", ""])
  }

  @MainActor
  @Test
  func previewSwitchesBetweenCompanionsWithoutChangingLegacyFile() throws {
    let context = try makeContext()
    let timeSeries = context.store.defaultDirectory.appendingPathComponent("Dev_Detecting_test.csv")
    let events = context.store.defaultDirectory.appendingPathComponent(
      "Localization_Detecting_test.csv")
    let legacyContents = "elapsed_time,speed_kmh,debug_message\n1.0,2.0,\"comma, and\nnewline\""
    try context.store.writeCSV(legacyContents, to: timeSeries)
    try context.store.writeCSV("event_id,model_name\n1,RC_CNN", to: events)
    let preview = CSVPreviewViewModel(csvURL: timeSeries, recordingFileStore: context.store)
    preview.load()
    #expect(preview.selectedKind == .timeSeries)
    #expect(preview.rows.first?.columns.last == "comma, and\nnewline")
    preview.select(.localization)
    #expect(preview.csvURL == events)
    #expect(preview.headers == ["event_id", "model_name"])
    preview.select(.timeSeries)
    #expect(preview.csvURL == timeSeries)
    #expect(try context.store.csvContents(at: timeSeries) == legacyContents)
  }

  @MainActor
  @Test
  func previewDistinguishesMissingEmptyAndMalformedCSV() throws {
    let context = try makeContext()
    let events = context.store.defaultDirectory.appendingPathComponent(
      "Localization_Detecting_test.csv")
    try context.store.writeCSV("event_id,model_name", to: events)
    let preview = CSVPreviewViewModel(csvURL: events, recordingFileStore: context.store)
    preview.load()
    #expect(preview.loadState == .empty)
    preview.select(.timeSeries)
    #expect(preview.loadState == .missing)
    try context.store.writeCSV("a,b\n1,\"unfinished", to: preview.csvURL)
    preview.load()
    #expect(preview.loadState == .failed)
    preview.select(.localization)
    #expect(preview.loadState == .empty)
  }

  @Test
  func speedReaderUsesHeaderNamesAndQuotedCSV() throws {
    let context = try makeContext()
    let audioURL = context.store.defaultDirectory.appendingPathComponent("Detecting_test.wav")
    try context.store.writeCSV(
      "elapsed_time,speed_kmh,debug_message\n1.5,12.0,\"message,with comma\"",
      to: audioURL.deletingPathExtension().appendingPathExtension("csv")
    )
    let details = PlayerRecordingDetailsController(
      recordingFileStore: context.store, userDefaults: context.defaults)
    #expect(details.speedRecords(for: audioURL).first?.time == 1.5)
    #expect(details.speedRecords(for: audioURL).first?.speed == "12.0")
  }

  private func makeContext() throws -> (store: RecordingFileStore, defaults: UserDefaults) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let store = RecordingFileStore(
      fileManager: .default, userDefaults: defaults, documentsDirectory: directory)
    try store.prepareStorage()
    return (store, defaults)
  }
}
