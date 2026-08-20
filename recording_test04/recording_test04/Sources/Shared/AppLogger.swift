import Foundation
import OSLog

enum AppLogger {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "dev.tuist.recording-test04"

  static let audio = Logger(subsystem: subsystem, category: "Audio")
  static let detection = Logger(subsystem: subsystem, category: "Detection")
  static let storage = Logger(subsystem: subsystem, category: "Storage")
}
