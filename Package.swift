// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyForge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "KeyForge", targets: ["KeyForge"])
    ],
    targets: [
        .executableTarget(
            name: "KeyForge",
            path: "Sources/KeyForge",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "KeyForgeTests",
            dependencies: ["KeyForge"],
            path: "Tests/KeyForgeTests"
        )
    ]
)
