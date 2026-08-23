import ProjectDescription

let project = Project(
  name: "recording_test04",
  targets: [
    .target(
      name: "recording_test04",
      destinations: .iOS,
      product: .app,
      bundleId: "dev.tuist.recording-test04",
      deploymentTargets: .iOS("18.0"),
      infoPlist: .extendingDefault(
        with: [
          "NSMicrophoneUsageDescription": "録音機能と音源の定位処理のためにマイクを使用します。",
          "NSLocationWhenInUseUsageDescription": "録音データに測定位置を記録するために位置情報を使用します。",
          "UILaunchScreen": [
            "UIColorName": "",
            "UIImageName": "",
          ],
        ]
      ),
      buildableFolders: [
        "recording_test04/Sources",
        "recording_test04/Resources",
      ],
      dependencies: []
    ),
    .target(
      name: "recording_test04Tests",
      destinations: .iOS,
      product: .unitTests,
      bundleId: "dev.tuist.recording-test04Tests",
      deploymentTargets: .iOS("18.0"),
      infoPlist: .default,
      buildableFolders: [
        "recording_test04/Tests"
      ],
      dependencies: [.target(name: "recording_test04")]
    ),
  ]
)
