/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation
internal import CCodeCoverageParser

internal typealias CParser = UnsafePointer<CCoverageParser>

public enum LLVMVersion: UInt8, Hashable, Equatable {
    case llvm17 = 17
    case llvm19 = 19
}

final class CoverageParserLibrary {
    private let library: UnsafeMutableRawPointer
    private let version: LLVMVersion
    private let instance: UnsafePointer<CCoverageParserLibrary>
    
    private init(from url: URL, version: LLVMVersion) throws {
        guard let lib = dlopen(url.path, RTLD_NOW) else {
            throw Error.dlopenFailed(path: url.path)
        }
        self.library = lib
        self.version = version
        guard let exports = dlsym(lib, "coverage_parser_library_instance") else {
            dlclose(lib)
            throw Error.symbolNotFound(name: "coverage_parser_library_instance")
        }
        self.instance = UnsafePointer(exports.assumingMemoryBound(to: CCoverageParserLibrary.self))
    }
    
    deinit {
        Self.cacheLock.whileLocked {
            Self.libraryCache.removeValue(forKey: version)
            dlclose(library)
        }
    }
    
    var llvmVersion: String {
        instance.llvmVersion
    }
    
    func createCoverageProcessor(binaries: [String]) -> Result<CParser, Error> {
        instance.createProcessor(binaries: binaries)
    }
    
    static func library(for llvm: LLVMVersion) -> Result<CoverageParserLibrary, Error> {
        cacheLock.whileLocked {
            if let library = libraryCache[llvm]?.value {
                return .success(library)
            }
            let bundle = Bundle(for: Self.self)
            guard let plugins = bundle.builtInPlugInsURL else {
                return .failure(.pluginsDirIsNil(bundle: bundle))
            }
            let libUrl = plugins
                .appendingPathComponent(llvm.libraryName + ".plugin", isDirectory: true)
                .appendingPathComponent(llvm.libraryName, isDirectory: false)
            do {
                let library = try Self(from: libUrl, version: llvm)
                libraryCache[llvm] = Weak(library)
                return .success(library)
            } catch let err as Error {
                return .failure(err)
            } catch {
                fatalError("unknown error: \(error)")
            }
        }
    }
    
    private static var libraryCache: [LLVMVersion: Weak<CoverageParserLibrary>] = [:]
    private static var cacheLock: UnfairLock = UnfairLock()
}

extension CoverageParserLibrary {
    enum Error: Swift.Error {
        case dlopenFailed(path: String)
        case pluginsDirIsNil(bundle: Bundle)
        case symbolNotFound(name: String)
        case plugin(error: String)
    }
}

extension UnsafePointer where Pointee == CCoverageParserLibrary {
    var llvmVersion: String {
        String(cString: pointee.llvm_version)
    }
    
    func createProcessor(binaries: [String]) -> Result<CParser, CoverageParserLibrary.Error> {
        let result = binaries.withCStringsArray {
            pointee.create_parser($0, UInt32($0.count))
        }
        if result.is_error {
            // Crash on empty error string. If is_error is set to true an error string should be set too.
            // It's more for development of C++ part
            defer { result.error!.deallocate() }
            return .failure(.plugin(error: String(cString: result.error!)))
        }
        return .success(result.parser!)
    }
}

extension UnsafePointer where Pointee == CCoverageParser {
    func filesCovered(in profilePath: String) -> Result<CCoverageFiles, CoverageParserLibrary.Error> {
        let result = pointee.covered_files(self, profilePath)
        if result.is_error {
            // Crash on empty error string. If is_error is set to true an error string should be set too.
            // It's more for development of C++ part
            defer { result.error!.deallocate() }
            return .failure(.plugin(error: String(cString: result.error!)))
        }
        return .success(result.files)
    }
    
    consuming func destroy() {
        pointee.destroy(UnsafeMutablePointer(mutating: self))
    }
}

private extension LLVMVersion {
    var libraryName: String {
        "CCodeCoverageParserLLVM" + String(rawValue, radix: 10)
    }
}
