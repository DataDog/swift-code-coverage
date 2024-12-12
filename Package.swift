// swift-tools-version:5.7.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "1.1.0"
let relaseChecksum = "80b6ff41d4c2e49d65e4c19c340d0dccc4ea8b7efb456d59e3825c48e1f90b8c"
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
