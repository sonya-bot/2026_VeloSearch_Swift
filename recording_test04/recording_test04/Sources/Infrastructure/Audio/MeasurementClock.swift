import Foundation

protocol MeasurementClock: Sendable {
  func now() -> TimeInterval
}

struct SystemMeasurementClock: MeasurementClock {
  func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
