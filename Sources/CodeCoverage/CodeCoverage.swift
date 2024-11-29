/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation
import CCoverageLLVM

public enum XcodeVersion: Hashable, Equatable {
    case xcode14
    case xcode15
    case xcode16
    
    var libraryName: String {
        return "CCoverageLLVM" + llvmVersion
    }
    
    var llvmVersion: String {
        switch self {
        case .xcode14, .xcode15: return "15"
        case .xcode16: return "17"
        }
    }
}

public final class CodeCoverage {
    public let coverageFilePath: String
    public let processor: CoverageProcessor
    public let tempDir: URL
    public private(set) var initialCoverage: CoverageInfo? = nil
    
    public init(processor: CoverageProcessor, coverageFile: String, temp: URL) {
        var fileName = coverageFile.replacingOccurrences(of: "%c", with: "")
        let continuous = fileName != coverageFile
        if fileName.range(of: "%m") == nil {
            fileName = fileName.replacingOccurrences(of: ".profraw", with: "%m.profraw")
        }
        self.coverageFilePath = fileName
        self.processor = processor
        self.tempDir = temp
        if coverageFile != fileName {
            if continuous {
                processor.disableContinuousMode()
            }
            setCoverageFile(to: fileName)
        }
        processor.writeCoverage()
        loadInitialCoverage()
    }
    
    public convenience init(for xcode: XcodeVersion, temp: URL, binaries: [CoveredBinary] = .currentProcessBinaries) throws {
        let coverageFile = try Self.currentCoverageFile
        let processor = try CoverageProcessor.create(for: xcode, binaries: binaries)
            .mapError(Error.processor)
            .get()
        self.init(processor: processor, coverageFile: coverageFile, temp: temp)
    }
    
    deinit {
        processor.writeCoverage()
    }
    
    public func startCoverageGathering() throws {
        let coverage = try Self.currentCoverageFile
        guard coverage == coverageFilePath else {
            throw Error.coverageGatheringAlreadyStarted
        }
        processor.writeCoverage()
        setCoverageFile(to: tempDir.appendingPathComponent(UUID().uuidString + ".profraw",
                                                           isDirectory: false).path)
        processor.resetCounters()
    }
    
    public func stopCoverageGathering() throws -> URL {
        let coverage = try Self.currentCoverageFile
        guard coverage.hasPrefix(tempDir.path) else {
            throw Error.coverageGatheringIsntStarted
        }
        processor.writeCoverage()
        setCoverageFile(to: coverageFilePath)
        return URL(fileURLWithPath: coverage, isDirectory: false)
    }
    
    public func filesCovered(in profile: URL) throws -> CoverageInfo {
        let covered = try processor.filesCovered(in: profile).get()
        return initialCoverage.map { $0.merged(with: covered) } ?? covered
    }
    
    public func setCoverageFile(to path: String) {
        setenv("LLVM_PROFILE_FILE", path, 1)
        processor.initializeCoverageFile()
    }
    
    public static var currentCoverageFile: String {
        get throws {
            guard let coverage = getenv("LLVM_PROFILE_FILE").map({ String(cString: $0) }) else {
                throw Error.coverageIsDisabled
            }
            return coverage
        }
    }
    
    private func loadInitialCoverage() {
        let covFileUrl = URL(fileURLWithPath: coverageFilePath, isDirectory: false)
        let covFileName = covFileUrl.lastPathComponent
        let resourceKeys = Set<URLResourceKey>([.isRegularFileKey, .nameKey])
        guard let enumerator = FileManager.default.enumerator(at: covFileUrl.deletingLastPathComponent(),
                                                              includingPropertiesForKeys: Array(resourceKeys),
                                                              options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        else { return }
        let file = enumerator.first {
            guard let fileURL = $0 as? URL else { return false }
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                  let isFile = resourceValues.isRegularFile, isFile,
                  let name = resourceValues.name
            else { return false }
            return name.hasSuffix(".profraw") && !covFileName.commonPrefix(with: name).isEmpty
        }.flatMap { $0 as? URL }
        if let file = file {
            self.initialCoverage = try? processor.filesCovered(in: file).get()
        }
    }
}

public extension CodeCoverage {
    enum Error: Swift.Error {
        case coverageIsDisabled
        case coverageGatheringAlreadyStarted
        case coverageGatheringIsntStarted
        case processor(error: CoverageProcessor.Error)
    }
}
