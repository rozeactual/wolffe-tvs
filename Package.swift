// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WolffeTV",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WolffeTV", targets: ["WolffeTV"])],
    targets: [
        .executableTarget(
            name: "WolffeTV",
            path: "Sources/WolffeTV"
        )
    ]
)
