// swift-tools-version:5.7.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "0.0.0"
let relaseChecksum = "aaaaaaaa"
let url = "https://github.com/DataDog/swift-code-coverage/releases/download/\(releaseVersion)/CodeCoverage.zip"

let package = Package(
    name: "swift-code-coverage",
    platforms: [.macOS(.v10_13), .macCatalyst(.v13), .iOS(.v11), .tvOS(.v11)],
    products: [
        .library(name: "CodeCoverage",
                 targets: ["CodeCoverage"]),
    ],
    targets: [
        .binaryTarget(name: "CodeCoverage",
                      url: url,
                      checksum: relaseChecksum)
    ]
)
