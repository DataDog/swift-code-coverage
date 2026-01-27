// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let releaseVersion = "2.0.0"
let relaseChecksum = "65bdc6f43d52eb10c2d07da46258a51c69f6c4a1d89baea3e6c65d92a2a976f4"
let url = "https://github.com/DataDog/swift-code-coverage/releases/download/\(releaseVersion)/CodeCoverageParser.zip"

var package = Package(
    name: "swift-code-coverage",
    platforms: [.macOS(.v10_13), .macCatalyst(.v13), .iOS(.v12), .tvOS(.v12)],
    products: [
        .library(name: "CodeCoverage",
                 targets: ["CodeCoverage"]),
        .library(name: "CodeCoverageParser",
                 targets: ["CodeCoverageParser"]),
        .library(name: "CodeCoverageCollector",
                 targets: ["CodeCoverageCollector"])
    ],
    targets: [
        .target(name: "CCodeCoverageCollector"),
        .target(name: "CodeCoverageCollector",
                dependencies: ["CCodeCoverageCollector"]),
        .target(name: "CodeCoverage",
                dependencies: ["CodeCoverageCollector",
                               "CodeCoverageParser"]),
        .testTarget(name: "CodeCoverageTests",
                    dependencies: ["CodeCoverage"])
    ]
)

if ProcessInfo.processInfo.environment["LOCAL_PARSER_BINARY"] == "1" {
    package.targets.append(.binaryTarget(name: "CodeCoverageParser",
                                         path: "build/xcframework/CodeCoverageParser.xcframework"))
} else {
    package.targets.append(.binaryTarget(name: "CodeCoverageParser",
                                         url: url,
                                         checksum: relaseChecksum))
}
