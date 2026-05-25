// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexWake",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexWake", targets: ["CodexWake"])
    ],
    targets: [
        .executableTarget(
            name: "CodexWake",
            path: "Sources/CodexWake",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
