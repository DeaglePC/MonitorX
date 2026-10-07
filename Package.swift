// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MonitorX",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "MonitorX",
            path: ".",
            exclude: ["Scripts", "build", "dist", "docs", "promo", "website",
                      "README.md", "PRIVACY.md", "Resources/AppStore.entitlements"],
            sources: ["Sources/MonitorX"],
            resources: [.copy("Resources/Localization")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
