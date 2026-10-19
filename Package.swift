// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ProxPulse", platforms: [.macOS(.v14)], products: [
    .executable(name: "ProxPulse", targets: ["ProxPulse"]),
    .library(name: "ProxPulseCore", targets: ["ProxPulseCore"])
], targets: [
    .target(name: "ProxPulseCore"),
    .target(name: "ProxPulseWidgetUI", dependencies: ["ProxPulseCore"]),
    .executableTarget(name: "ProxPulse", dependencies: ["ProxPulseCore", "ProxPulseWidgetUI"]),
    .testTarget(name: "ProxPulseCoreTests", dependencies: ["ProxPulseCore"])
], swiftLanguageModes: [.v6])
