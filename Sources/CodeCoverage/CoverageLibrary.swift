/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import CCoverageLLVM

final class CoverageLibrary {
    private let library: UnsafeMutableRawPointer
    private let version: XcodeVersion
    private let exports: llvm_coverage_library_exports
    
    private init(from url: URL, version: XcodeVersion) throws {
        guard let lib = dlopen(url.path, RTLD_NOW) else {
            throw Error.dlopenFailed(path: url.path)
        }
        self.library = lib
        self.version = version
        guard let exports = dlsym(lib, "llvm\(version.llvmVersion)_coverage_library_exports") else {
            dlclose(lib)
            throw Error.symbolNotFound(name: "llvm\(version.llvmVersion)_coverage_library_exports")
        }
        self.exports = exports.assumingMemoryBound(to: llvm_coverage_library_exports.self).pointee
    }
    
    deinit {
        Self.cacheLock.whileLocked {
            Self.libraryCache.removeValue(forKey: version)
            dlclose(library)
        }
    }
    
    func createCoverageProcessor(binaries: [String]) -> Result<CCoverageProcessor, Error> {
        let result = binaries.withCStringsArray {
            exports.init_processor($0, UInt32(binaries.count))
        }
        if result.is_error {
            // Crash on empty error string. If is_error is set to true an error string should be set too.
            // It's more for development of C++ part
            defer { result.error!.deallocate() }
            return .failure(.plugin(error: String(cString: result.error!)))
        }
        return .success(result.processor!)
    }
    
    func destroyCoverageProcessor(_ processor: CCoverageProcessor) {
        exports.destroy_processor(processor)
    }
    
    func filesCovered(in profilePath: String, processor: CCoverageProcessor) -> Result<CCoverageFiles, Error> {
        let result = exports.covered_files(processor, profilePath)
        if result.is_error {
            // Crash on empty error string. If is_error is set to true an error string should be set too.
            // It's more for development of C++ part
            defer { result.error!.deallocate() }
            return .failure(.plugin(error: String(cString: result.error!)))
        }
        return .success(result.files)
    }
    
    func resetCounters(profile version: UInt64,
                       counters: (begin: UnsafeRawPointer, end: UnsafeRawPointer),
                       data: (begin: UnsafeRawPointer, end: UnsafeRawPointer),
                       bitmap: (begin: UnsafeRawPointer, end: UnsafeRawPointer)?) -> Result<(), Error>
    {
        let error = exports.reset_counters(version, counters.begin, counters.end,
                                           data.begin, data.end, bitmap?.begin, bitmap?.end)
        defer { error?.deallocate() }
        return error.map { .failure(.plugin(error: String(cString: $0))) } ?? .success(())
    }
    
    static func library(for xcode: XcodeVersion) -> Result<CoverageLibrary, Error> {
        cacheLock.whileLocked {
            if let library = libraryCache[xcode]?.value {
                return .success(library)
            }
            let bundle = Bundle(for: Self.self)
            guard let plugins = bundle.builtInPlugInsURL else {
                return .failure(.pluginsDirIsNil(bundle: bundle))
            }
            let libUrl = plugins
                .appendingPathComponent(xcode.libraryName + ".plugin", isDirectory: true)
                .appendingPathComponent(xcode.libraryName, isDirectory: false)
            do {
                let library = try Self(from: libUrl, version: xcode)
                libraryCache[xcode] = Weak(library)
                return .success(library)
            } catch let err as Error {
                return .failure(err)
            } catch {
                fatalError("unknown error: \(error)")
            }
        }
    }
    
    private static var libraryCache: [XcodeVersion: Weak<CoverageLibrary>] = [:]
    private static var cacheLock: UnfairLock = UnfairLock()
}

extension CoverageLibrary {
    enum Error: Swift.Error {
        case dlopenFailed(path: String)
        case pluginsDirIsNil(bundle: Bundle)
        case symbolNotFound(name: String)
        case plugin(error: String)
    }
}
