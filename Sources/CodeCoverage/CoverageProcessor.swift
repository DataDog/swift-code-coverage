/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import CCoverageLLVM

public final class CoverageProcessor {
    public let binaries: [CoveredBinary]
    
    private let library: CoverageLibrary
    private let processor: CCoverageProcessor
    
    private init(library: CoverageLibrary, binaries: [CoveredBinary] = .currentProcessBinaries) throws {
        let binariesPath = binaries.map { $0.path }
        let processor = try library.createCoverageProcessor(binaries: binariesPath).mapError {
            switch $0 {
            case .plugin(error: let err): return Error.processorInitFailed(error: err)
            default: return Error(from: $0)
            }
        }.get()
        self.library = library
        self.binaries = binaries
        self.processor = processor
    }
    
    public func filesCovered(in profile: URL) -> Result<CoverageInfo, Error> {
        library.filesCovered(in: profile.path, processor: processor)
            .mapError(Error.init)
            .map { CoverageInfo(cValue: $0) }
    }
    
    public func writeCoverage() {
        for binary in binaries {
            binary.write()
        }
    }
    
    public func initializeCoverageFile() {
        for binary in binaries {
            binary.initializeProfileFile()
        }
    }
    
    public func disableContinuousMode() {
        for binary in binaries {
            binary.setPageSize(0)
        }
    }
    
    public func resetCounters() {
        for binary in binaries {
            library.resetCounters(counters: binary.countersFunc, data: binary.dataFunc)
        }
    }
    
    deinit {
        library.destroyCoverageProcessor(processor)
    }
    
    static func create(for xcode: XcodeVersion,
                       binaries: [CoveredBinary] = .currentProcessBinaries) -> Result<CoverageProcessor, Error>
    {
        CoverageLibrary.library(for: xcode)
            .mapError(Error.init)
            .flatMap { library in
                do {
                    return .success(try Self(library: library, binaries: binaries))
                } catch let err as Error {
                    return .failure(err)
                } catch {
                    fatalError("unknown error: \(error)")
                }
            }
    }
}

public extension CoverageProcessor {
    enum Error: Swift.Error {
        case dlopenFailed(path: String)
        case pluginsDirIsNil(bundle: Bundle)
        case symbolNotFound(name: String)
        case processorInitFailed(error: String)
        case llvm(error: String)
        
        init(from err: CoverageLibrary.Error) {
            switch err {
            case .dlopenFailed(path: let p): self = .dlopenFailed(path: p)
            case .pluginsDirIsNil(bundle: let b): self = .pluginsDirIsNil(bundle: b)
            case .symbolNotFound(name: let n): self = .symbolNotFound(name: n)
            case .plugin(error: let e): self = .llvm(error: e)
            }
        }
    }
}
