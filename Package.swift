// swift-tools-version:5.9
import PackageDescription

// ParkLifeCore is deliberately platform-agnostic: Foundation only, no SwiftUI/SpriteKit/
// UIKit/CloudKit. That keeps the simulation headless-testable (including on Linux CI) and
// mechanically prevents rendering or UI code from leaking into simulation logic.
let package = Package(
    name: "ParkLife",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ParkLifeCore", targets: ["ParkLifeCore"])
    ],
    targets: [
        .target(
            name: "ParkLifeCore",
            path: "Sources/ParkLifeCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ParkLifeCoreTests",
            dependencies: ["ParkLifeCore"],
            path: "Tests/ParkLifeCoreTests"
        )
    ]
)
