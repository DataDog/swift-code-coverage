/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation
internal import CCodeCoverageParser

public final class CoverageParser {
    public let binaries: [URL]
    public private(set) var initialCoverage: CoverageInfo? = nil
    public var llvmVersion: String { library.llvmVersion }
    
    private let library: CoverageParserLibrary
    private let processor: CParser
    
    private init(library: CoverageParserLibrary, binaries: [URL], initialCodeCoverage: String?) throws {
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
        if let path = initialCodeCoverage,
           let file = Self.initialCoverageFileURL(coverageFilePath: path)
        {
            self.initialCoverage = try filesCovered(in: file)
        }
    }
    
    public convenience init(for llvm: LLVMVersion,
                            binaries: [URL],
                            initialCodeCoverage: String? = nil) throws
    {
        let library = try CoverageParserLibrary.library(for: llvm).mapError(Error.init).get()
        try self.init(library: library, binaries: binaries, initialCodeCoverage: initialCodeCoverage)
    }
    
    public func filesCovered(in profile: URL) throws -> CoverageInfo {
        try processor.filesCovered(in: profile.path)
            .mapError(Error.init)
            .map { CoverageInfo(cValue: $0) }.get()
    }
    
    deinit {
        processor.destroy()
    }
    
    public static func initialCoverageFileURL(coverageFilePath: String) -> URL? {
        let covFileUrl = URL(fileURLWithPath: coverageFilePath, isDirectory: false)
        let covFileName = covFileUrl.lastPathComponent
        let resourceKeys = Set<URLResourceKey>([.isRegularFileKey, .nameKey])
        guard let enumerator = FileManager.default.enumerator(at: covFileUrl.deletingLastPathComponent(),
                                                              includingPropertiesForKeys: Array(resourceKeys),
                                                              options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        else { return nil }
        return enumerator.first {
            guard let fileURL = $0 as? URL else { return false }
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                  let isFile = resourceValues.isRegularFile, isFile,
                  let name = resourceValues.name
            else { return false }
            return name.hasSuffix(".profraw") && !covFileName.commonPrefix(with: name).isEmpty
        }.flatMap { $0 as? URL }
    }
}

public extension CoverageParser {
    enum Error: Swift.Error {
        case dlopenFailed(path: String)
        case pluginsDirIsNil(bundle: Bundle)
        case symbolNotFound(name: String)
        case processorInitFailed(error: String)
        case llvm(error: String)
        
        init(from err: CoverageParserLibrary.Error) {
            switch err {
            case .dlopenFailed(path: let p): self = .dlopenFailed(path: p)
            case .pluginsDirIsNil(bundle: let b): self = .pluginsDirIsNil(bundle: b)
            case .symbolNotFound(name: let n): self = .symbolNotFound(name: n)
            case .plugin(error: let e): self = .llvm(error: e)
            }
        }
    }
}
