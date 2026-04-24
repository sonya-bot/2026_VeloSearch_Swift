import ProjectDescription

let project = Project(
    name: "recording_test02",
    targets: [
        .target(
            name: "recording_test02",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.recording-test02",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            buildableFolders: [
                "recording_test02/Sources",
                "recording_test02/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "recording_test02Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.recording-test02Tests",
            infoPlist: .default,
            buildableFolders: [
                "recording_test02/Tests"
            ],
            dependencies: [.target(name: "recording_test02")]
        ),
    ]
)
