import ProjectDescription

let project = Project(
    name: "recoding_test01",
    targets: [
        .target(
            name: "recoding_test01",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.recoding-test01",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    "NSLocationWhenINUseUsageDescription": "このアプリは録音と位置情報の取得のためにマイクと位置情報へのアクセスを必要とします。"
                    ],
                ]
            ),
            buildableFolders: [
                "recoding_test01/Sources",
                "recoding_test01/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "recoding_test01Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.recoding-test01Tests",
            infoPlist: .default,
            buildableFolders: [
                "recoding_test01/Tests"
            ],
            dependencies: [.target(name: "recoding_test01")]
        ),
    ]
)
