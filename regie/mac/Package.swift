// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Regie",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Regie",
            path: "Sources/Regie"
        )
    ]
)
