// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PinchDial",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PinchDial", targets: ["PinchDial"])],
    targets: [
        .target(name: "PinchDialCore"),
        .executableTarget(name: "PinchDial", dependencies: ["PinchDialCore"]),
        .testTarget(name: "PinchDialCoreTests", dependencies: ["PinchDialCore"])
    ]
)
