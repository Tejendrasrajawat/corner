// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Corner",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure model, parsing and formatting: no AppKit, so it is unit-testable.
        .target(name: "CornerKit"),
        .executableTarget(name: "Corner", dependencies: ["CornerKit"]),
        .testTarget(name: "CornerKitTests", dependencies: ["CornerKit"]),
    ]
)
