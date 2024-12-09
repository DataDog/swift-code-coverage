// swift-tools-version:5.7.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "1.0.0"
let relaseChecksum = "f6d8a484134ff6087f274c7cf64b7760be0dbac38788a9bbab35b876fd540968"
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
