// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TripleTap",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "tripletap", targets: ["TripleTap"])
    ],
    targets: [
        .executableTarget(name: "TripleTap"),
        .testTarget(name: "TripleTapTests", dependencies: ["TripleTap"])
    ]
)
