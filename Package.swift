// swift-tools-version:5.7.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "1.1.1"
let relaseChecksum = "15e5f449ad28605d8006db42e162731fcc21fb2a16a0d3956022cfbdb4e9ad08"
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
