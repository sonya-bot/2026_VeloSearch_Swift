// swift-tools-version: 6.0
import PackageDescription

#if TUIST
  import struct ProjectDescription.PackageSettings

  let packageSettings = PackageSettings(
    productTypes: [:],
    // Xcode 27 rejects older deployment targets in Firebase's transitive dependencies.
    baseSettings: .settings(base: ["IPHONEOS_DEPLOYMENT_TARGET": "18.0"])
  )
#endif

let package = Package(
  name: "recording_test04",
  dependencies: [
    .package(
      url: "https://github.com/firebase/firebase-ios-sdk.git",
      from: "12.0.0"
    )
  ]
)
