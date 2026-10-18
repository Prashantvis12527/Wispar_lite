// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WisprLite",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "WisprLite", path: "Sources/WisprLite")
    ]
)
