/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import XCTest
@testable import CodeCoverage

func test234() {}

func test123() {
    test234()
}

func test456() {
    test123()
}

final class CodeCoverageTests: XCTestCase {
    nonisolated(unsafe) static var coverage: CoverageProcessor! = nil
    
    static let xcodeVersion: XcodeVersion = .compiledBy!
    
    class override func setUp() {
        Self.coverage = try! CoverageProcessor(for: xcodeVersion,
                                               temp: URL(fileURLWithPath: NSTemporaryDirectory(),
                                                         isDirectory: true))
    }
    
    override class func tearDown() {
        Self.coverage = nil
    }

    func testVersion() {
        let version = Self.coverage!.llvmVersion
        XCTAssert(version.hasPrefix(String(Self.xcodeVersion.llvmVersion.rawValue)),
                  "Wrong version: \(version), expected: \(Self.xcodeVersion.llvmVersion.rawValue).*")
    }
    
    func testSimple() throws {
        let coverage = Self.coverage!
        
        try coverage.startCoverageGathering()
        test123()
        let file = try coverage.stopCoverageGathering()
        
        defer { try? FileManager.default.removeItem(at: file) }
        
        let covered = try coverage.filesCovered(in: file)
        print(covered)
    }
    
    func testAdvanced() throws {
        let coverage = Self.coverage!
        
        try coverage.startCoverageGathering()
        test456()
        let file = try coverage.stopCoverageGathering()
        defer { try? FileManager.default.removeItem(at: file) }
        
        let covered = try coverage.filesCovered(in: file)
        print(covered)
    }

    func testPerformanceExample() {
        let coverage = Self.coverage!
        self.measure {
            try! coverage.startCoverageGathering()
            test123()
            let file = try! coverage.stopCoverageGathering()
            defer { try? FileManager.default.removeItem(at: file) }
            let _ = try! coverage.filesCovered(in: file)
        }
    }
    
    func testMultithreadedParsing() throws {
        let iterations = 100
        let files = try (0..<iterations).map { index in
            try Self.coverage.startCoverageGathering()
            if index % 2 == 0 {
                test123()
            } else {
                test456()
            }
            return try Self.coverage.stopCoverageGathering()
        }
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let file = files[index]
            defer { try? FileManager.default.removeItem(at: file) }
            let _ = try! Self.coverage.filesCovered(in: file)
        }
    }
}
