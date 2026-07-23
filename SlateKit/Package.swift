// swift-tools-version: 6.0

// SlateKit is Slate's domain core: entities, value objects, domain policies,
// and application use cases. It depends on Foundation only, so it builds and
// tests anywhere Swift runs — macOS, Linux, and inside the iOS app.
import PackageDescription

let package = Package(
    name: "SlateKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SlateKit", targets: ["SlateKit"]),
    ],
    targets: [
        .target(name: "SlateKit"),
        .testTarget(name: "SlateKitTests", dependencies: ["SlateKit"]),
    ],
    swiftLanguageModes: [.v6]
)
