import ProjectDescription

let project = Project(
    name: "recording_test03",
    targets: [
        .target(
            name: "recording_test03",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.recording-test03",
            infoPlist: .extendingDefault(
                with: [
                    // 実機で録音・位置情報を使うため、未設定だとアクセス時にアプリが終了する。
                    "NSMicrophoneUsageDescription": "録音機能と音源の定位処理のためにマイクを使用します。",
                    "NSLocationWhenInUseUsageDescription": "録音データに測定位置を記録するために位置情報を使用します。",
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            buildableFolders: [
                "recording_test03/Sources",
                "recording_test03/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "recording_test03Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.recording-test03Tests",
            infoPlist: .default,
            buildableFolders: [
                "recording_test03/Tests"
            ],
            dependencies: [.target(name: "recording_test03")]
        ),
    ]
)
