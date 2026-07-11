// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clap",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Clap",
            path: "Sources/Clap"
        )
    ]
)
