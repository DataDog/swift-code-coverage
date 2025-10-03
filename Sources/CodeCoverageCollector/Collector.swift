/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation
internal import CCodeCoverageCollector

public final class CoverageCollector {
    public let coverageFilePath: String
    public let tempDir: URL
    public let xcode: XcodeVersion
    public let binaries: [CoveredBinary]
    
    private var currentFileIndex: UInt64 = 0
    private let processId: Int32
    
    public init(coverageFile: String, temp: URL, xcode: XcodeVersion, binaries: [CoveredBinary]) {
        let (fileName, changed, continuous) = Self.fixFileName(coverageFile: coverageFile)
        self.binaries = binaries
        self.xcode = xcode
        self.coverageFilePath = fileName
        self.processId = ProcessInfo.processInfo.processIdentifier
        self.tempDir = temp
        if changed {
            if continuous {
                binaries.disableContinuousMode()
            }
            setCoverageFile(to: fileName)
        }
        binaries.writeCoverage()
    }
    
    public convenience init(for xcode: XcodeVersion,
                            temp: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
                            binaries: [CoveredBinary] = .currentProcessBinaries) throws
    {
        let coverageFile = try Self.currentCoverageFile
        self.init(coverageFile: coverageFile, temp: temp, xcode: xcode, binaries: binaries)
    }
    
    deinit {
        binaries.writeCoverage()
    }
    
    public func startCoverageGathering() throws {
        let coverage = try Self.currentCoverageFile
        guard coverage == coverageFilePath else {
            throw Error.coverageGatheringAlreadyStarted
        }
        binaries.writeCoverage()
        let fileName = "code-coverage-\(processId)-\(currentFileIndex).profraw"
        currentFileIndex = currentFileIndex.addingReportingOverflow(1).partialValue
        setCoverageFile(to: tempDir.appendingPathComponent(fileName, isDirectory: false).path)
        try binaries.resetCounters(xcode: xcode)
    }
    
    public func stopCoverageGathering() throws -> URL {
        let coverage = try Self.currentCoverageFile
        guard coverage.hasPrefix(tempDir.path) else {
            throw Error.coverageGatheringIsntStarted
        }
        binaries.writeCoverage()
        setCoverageFile(to: coverageFilePath)
        return URL(fileURLWithPath: coverage, isDirectory: false)
    }
    
    public func setCoverageFile(to path: String) {
        setenv(Constants.llvmProfileFile, path, 1)
        binaries.initializeCoverageFile()
    }
    
    public static var currentCoverageFile: String {
        get throws {
            guard let coverage = getenv(Constants.llvmProfileFile).map({ String(cString: $0) }) else {
                throw Error.coverageIsDisabled
            }
            return coverage
        }
    }
    
    private static func fixFileName(coverageFile: String) -> (newName: String, isChanged: Bool, isContinuous: Bool) {
        var fileName = coverageFile.replacingOccurrences(of: "%c", with: "")
        let continuous = fileName.count != coverageFile.count
        var changed = continuous
        if fileName.range(of: "%m") == nil {
            fileName = fileName.replacingOccurrences(of: ".profraw", with: "%m.profraw")
            changed = true
        }
        return (fileName, changed, continuous)
    }
}

public extension CoverageCollector {
    enum Error: Swift.Error {
        case coverageIsDisabled
        case coverageGatheringAlreadyStarted
        case coverageGatheringIsntStarted
        case binaryBitmapCallbacksAreNil
    }
}

