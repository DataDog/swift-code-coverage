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
    static var coverage: CodeCoverage! = nil

#if swift(>=5.10)
    static let xcodeVersion: XcodeVersion = .xcode16
#elseif swift(>=5.9) && swift(<5.10)
    static let xcodeVersion: XcodeVersion = .xcode15
#elseif swift(>=5.7) && swift(<5.9)
    static let xcodeVersion: XcodeVersion = .xcode14
#else
    #error("Unsupported Xcode version")
#endif
    
    class override func setUp() {
        Self.coverage = try! CodeCoverage(for: xcodeVersion,
                                          temp: URL(fileURLWithPath: NSTemporaryDirectory(),
                                                    isDirectory: true))
    }
    
    override class func tearDown() {
        Self.coverage = nil
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

    func testPerformanceExample() throws {
        let coverage = Self.coverage!
        self.measure {
            try! coverage.startCoverageGathering()
            test123()
            let file = try! coverage.stopCoverageGathering()
            defer { try? FileManager.default.removeItem(at: file) }
            let _ = try! coverage.filesCovered(in: file)
        }
    }
}
