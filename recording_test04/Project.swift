import ProjectDescription

let project = Project(
  name: "recording_test04",
  targets: [
    .target(
      name: "recording_test04",
      destinations: .iOS,
      product: .app,
      bundleId: "jp.cocolab.recording-test",
      deploymentTargets: .iOS("18.0"),
      infoPlist: .extendingDefault(
        with: [
          "CFBundleDisplayName": "MimiRec",
          "NSMicrophoneUsageDescription": "録音機能と音源の定位処理のためにマイクを使用します。",
          "NSLocationWhenInUseUsageDescription": "録音データに測定位置を記録するために位置情報を使用します。",
          "FirebaseAppDelegateProxyEnabled": false,
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
      dependencies: [
        .external(name: "FirebaseAnalyticsCore"),
        .external(name: "FirebaseCore"),
      ],
      settings: .settings(
        base: [
          "CURRENT_PROJECT_VERSION": "1",
          "DEVELOPMENT_TEAM": "6UM4BFJ6K3",
          "MARKETING_VERSION": "1.0",
          "OTHER_LDFLAGS": "$(inherited) -ObjC"
        ]
      )
    ),
    .target(
      name: "recording_test04Tests",
      destinations: .iOS,
      product: .unitTests,
      bundleId: "jp.cocolab.recording-test.tests",
      deploymentTargets: .iOS("18.0"),
      infoPlist: .default,
      buildableFolders: [
        "recording_test04/Tests"
      ],
      dependencies: [.target(name: "recording_test04")],
      settings: .settings(
        base: [
          "DEVELOPMENT_TEAM": "6UM4BFJ6K3"
        ]
      )
    ),
  ]
)
