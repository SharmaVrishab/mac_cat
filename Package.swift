// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Command Line Tools keep Swift Testing's macros in a nested plugin folder that
// incremental builds do not always search. Xcode's toolchain already finds them.
let testingMacros = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingMacros)
    ? [.unsafeFlags(["-plugin-path", testingMacros])]
    : []

let package = Package(
    name: "Miso",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Miso", targets: ["Miso"])
    ],
    targets: [
        .executableTarget(
            name: "Miso",
            path: "Sources/Miso"
        ),
        .testTarget(
            name: "MisoTests",
            dependencies: ["Miso"],
            path: "Tests/MisoTests",
            swiftSettings: testSettings
        ),
    ]
)
