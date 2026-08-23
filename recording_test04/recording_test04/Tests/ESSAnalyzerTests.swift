import XCTest

@testable import recording_test04

final class ESSAnalyzerTests: XCTestCase {
  func testIdenticalReferenceProducesFiniteNormalizedResponse() throws {
    let sweep = (0..<2_048).map { index in
      Float(sin(2 * Double.pi * Double(index) / 47))
    }
    let preSilenceFrames = 128
    let recording = [Float](repeating: 0, count: preSilenceFrames) + sweep

    let result = try ESSAnalyzer().analyze(
      recordedChannels: [recording, recording],
      sweep: sweep,
      preSilenceFrames: preSilenceFrames,
      sampleRate: 48_000
    )

    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result[0].impulseResponse.count, recording.count)
    XCTAssertTrue(result[0].response.allSatisfy { $0.rawDecibels.isFinite })
    let oneKilohertz = try XCTUnwrap(
      result[0].response.min { abs($0.frequency - 1_000) < abs($1.frequency - 1_000) }
    )
    XCTAssertEqual(oneKilohertz.rawDecibels, 0, accuracy: 0.001)
  }
}
