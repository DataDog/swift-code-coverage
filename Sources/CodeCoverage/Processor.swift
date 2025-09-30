/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation
@_exported import CodeCoverageCollector
@_exported import CodeCoverageParser

public struct CoverageProcessor {
    public let collector: CoverageCollector
    public let parser: CoverageParser
    
    public var initialCoverage: CoverageInfo? { parser.initialCoverage }
    public var llvmVersion: String { parser.llvmVersion }
    public var tempDir: URL { collector.tempDir }
    public var binaries: [CoveredBinary] { collector.binaries }
    
    public init(collector: CoverageCollector, parser: CoverageParser) {
        self.collector = collector
        self.parser = parser
    }
    
    public init(for xcode: XcodeVersion, temp: URL, binaries: [CoveredBinary] = .currentProcessBinaries) throws {
        let (collector, parser) = try Self.mapError {
            let collector = try CoverageCollector(for: xcode, temp: temp, binaries: binaries)
            return try (collector, CoverageParser(for: collector, loadInitialCoverage: true))
        }
        self.init(collector: collector, parser: parser)
    }
    
    public func startCoverageGathering() throws {
        try Self.mapError { try collector.startCoverageGathering() }
    }
    
    public func stopCoverageGathering() throws -> URL {
        try Self.mapError { try collector.stopCoverageGathering() }
    }
    
    public func filesCovered(in profile: URL) throws -> CoverageInfo {
        try Self.mapError { try parser.filesCovered(in: profile) }
    }
    
    public func setCoverageFile(to path: String) {
        collector.setCoverageFile(to: path)
    }
    
    public static var currentCoverageFile: String {
        get throws {
            try Self.mapError { try CoverageCollector.currentCoverageFile }
        }
    }
    
    private static func mapError<T>(_ cb: () throws -> T) rethrows -> T {
        do {
            return try cb()
        } catch {
            throw try Error(from: error)
        }
    }
}

public extension CoverageProcessor {
    enum Error: Swift.Error {
        case collector(error: CoverageCollector.Error)
        case parser(error: CoverageParser.Error)
        
        init(from error: any Swift.Error) throws {
            switch error {
            case let err as CoverageCollector.Error:
                self = .collector(error: err)
            case let err as CoverageParser.Error:
                self = .parser(error: err)
            default:
                throw error
            }
        }
    }
}

public extension XcodeVersion {
    var llvmVersion: LLVMVersion {
        switch self {
        case .xcode16_0: return .llvm17
        case .xcode16_3, .xcode26: return .llvm19
        @unknown default: fatalError("Unknown Xcode version \(self). Should never happen")
        }
    }
}

public extension CoverageParser {
    convenience init(for collector: CoverageCollector, loadInitialCoverage: Bool = true) throws {
        try self.init(for: collector.xcode.llvmVersion,
                      binaries: collector.binaries.map(\.url),
                      initialCodeCoverage: loadInitialCoverage ? collector.coverageFilePath : nil)
    }
}
