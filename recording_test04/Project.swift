import ProjectDescription

let project = Project(
    name: "recording_test04",
    targets: [
        .target(
            name: "recording_test04",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.recording-test04",
            infoPlist: .extendingDefault(
                with: [
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
            infoPlist: .default,
            buildableFolders: [
                "recording_test04/Tests"
            ],
            dependencies: [.target(name: "recording_test04")]
        ),
    ]
)
