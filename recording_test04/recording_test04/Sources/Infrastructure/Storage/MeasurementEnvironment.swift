import Darwin
import Foundation
import UIKit

struct MeasurementEnvironment {
  let deviceModel: String
  let osVersion: String
  let appVersion: String
  let buildNumber: String

  static func current(bundle: Bundle) -> Self {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = withUnsafeBytes(of: &systemInfo.machine) { bytes in
      String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
    return Self(
      deviceModel: ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine,
      osVersion: UIDevice.current.systemVersion,
      appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "不明",
      buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "不明"
    )
  }

  var versionLabel: String { "\(appVersion) (\(buildNumber))" }
}
