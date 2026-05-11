// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let releaseVersion = "2.1.0"
let relaseChecksum = "298b37d1736ecac6584259c7bd236cf6ae1e21c0831dbce2dda033315b4e9ddf"
let url = "https://github.com/DataDog/swift-code-coverage/releases/download/\(releaseVersion)/CodeCoverageParser.zip"

var package = Package(
    name: "swift-code-coverage",
    platforms: [.macOS(.v11), .macCatalyst(.v14), .iOS(.v15), .tvOS(.v15), .watchOS(.v8), .visionOS(.v1)],
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
