// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cliche",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Cliche",
            path: "Sources/Cliche"
        )
    ]
)
