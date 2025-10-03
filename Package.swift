// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let releaseVersion = "1.2.0"
let relaseChecksum = "6fedb29929e454764583dfeb54fdffa47b76c8ca25474a8c9867aac466d7cb98"
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
