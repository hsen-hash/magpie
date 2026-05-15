// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Magpie",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Magpie",
            path: "Sources/Magpie"
        )
    ]
)
