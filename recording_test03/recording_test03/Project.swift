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
