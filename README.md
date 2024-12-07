# Swift Code Coverage collector for Datadog Test Optimization

This library is a part of Datadog's [Test Optimization](https://docs.datadoghq.com/tests/) product.

## Getting Started

This library allows to gather coverage programmatically.

It injects itself into the LLVM profiler, so depends on it and allows to use common code coverage at the same time (merges coverage back).

It doesn't work with Continuos Mode of LLVM profiler, library will disable it automatically.

Right now library supports Xcode 14 - 16 versions (LLVM 15-17).

Start and stop methods of the library are not thread safe! File coverage parsing is thread safe and can be called from the background threads.

## How to use

### Installation
Add this repository to the SPM dependencies.

```swift
.package(url: "https://github.com/DataDog/swift-code-coverage.git", from: "1.0.0")
```

### Example
```swift
import CodeCoverage

let coverage = try CoverageCollector(for: .xcode16, temp: NSTemporaryDirectory())

// Collected on the initialisaion
print("Initial coverage: \(coverage.initialCoverage)")

// start coverage gathering
try coverage.startCoverageGathering()

// call some methods
// coverage will be gathered by LLVM profiler

// write gathered coverage to file and return its URL
let profraw = try coverage.stopCoverageGathering()

// parse gathered coverage
let gathered = try coverage.filesCovered(in: profraw)

//remove profraw temporary file
try FileManager.default.removeItem(at: profraw)

print("Gathered coverage: \(gathered)")
```

## Building

1. Build LLVM libraries with `make -f Makefile.llvm build` command.
2. Open Xcode project and edit.
3. To build xcarchive use `make build` command.

## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](CONTRIBUTING.md).

## License

[Apache License, v2.0](LICENSE)
