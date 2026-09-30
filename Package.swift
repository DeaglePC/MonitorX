// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MonitorX",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "MonitorX",
            path: "Sources/MonitorX",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
