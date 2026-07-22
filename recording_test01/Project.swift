import ProjectDescription

let project = Project(
    name: "recording_test01",
    targets: [
        .target(
            name: "recording_test01",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.recording-test01",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ], // ← ここでちゃんとカッコを閉じる
                    "NSLocationWhenInUseUsageDescription": "このアプリは録音と位置情報の取得のためにマイクと位置情報へのアクセスを必要とします。",
                    "NSMicrophoneUsageDescription": "このアプリは録音のためにマイクへのアクセスを必要とします。" // 録音用にマイクの許可も追加
                ]
            ),
            buildableFolders: [
                "recording_test01/Sources",
                "recording_test01/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "recording_test01Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.recording-test01Tests", // ← rを追加して修正
            infoPlist: .default,
            buildableFolders: [
                "recording_test01/Tests"
            ],
            dependencies: [.target(name: "recording_test01")]
        ),
    ]
)