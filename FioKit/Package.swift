// swift-tools-version: 6.0

// FioKit is Fio's domain core: entities, value objects, domain policies,
// and application use cases. It depends on Foundation only, so it builds and
// tests anywhere Swift runs — macOS, Linux, and inside the iOS app.
import PackageDescription

let package = Package(
    name: "FioKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "FioKit", targets: ["FioKit"]),
    ],
    targets: [
        .target(name: "FioKit"),
        .testTarget(name: "FioKitTests", dependencies: ["FioKit"]),
    ],
    swiftLanguageModes: [.v6]
)
