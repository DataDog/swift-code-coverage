/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation
import CCoverageLLVM

public struct CoverageInfo: Hashable, Equatable, Codable {
    public let files: [String: File]
    
    public struct File: Hashable, Equatable, Codable {
        public let name: String
        public let segments: [Location: Segment]
    }
    
    public struct Segment: Hashable, Equatable, Codable {
        public let location: Location
        public let count: UInt64
    }
    
    public struct Location: Hashable, Equatable, Codable {
        public var startLine: UInt32
        public var startColumn: UInt32
        public var endLine: UInt32
        public var endColumn: UInt32
    }
    
    public func merged(with other: Self) -> Self {
        var files = self.files
        for ofile in other.files.values {
            if let file = files[ofile.name] {
                var segments = file.segments
                for osegment in ofile.segments.values {
                    if let segment = segments[osegment.location] {
                        segments[osegment.location] = Segment(location: osegment.location,
                                                              count: segment.count + osegment.count)
                    } else {
                        segments[osegment.location] = osegment
                    }
                }
                files[ofile.name] = File(name: file.name, segments: segments)
            } else {
                files[ofile.name] = ofile
            }
        }
        return Self(files: files)
    }
}

extension CoverageInfo {
    public init(cValue: CoveredFiles) {
        defer { cValue.files?.deallocate() }
        let pairs = cValue.bufPtr.map { File(cValue: $0) }.map { ($0.name, $0) }
        self.files = Dictionary(uniqueKeysWithValues: pairs)
    }
}

extension CoverageInfo: CustomDebugStringConvertible {
    public var debugDescription: String {
        let info = files.values.map { $0.debugDescription }.joined(separator: "\n")
        return "CoverageInfo:\n===========\n\(info)"
    }
}

extension CoverageInfo.File {
    public init(cValue: FileCoverage) {
        defer {
            cValue.name.deallocate()
            cValue.segments?.deallocate()
        }
        self.name = String(cString: cValue.name)
        
        guard cValue.segments_count > 0 else {
            self.segments = [:]
            return
        }
        
        var segments = [CoverageInfo.Location: CoverageInfo.Segment]()
        segments.reserveCapacity(cValue.segments_count)
        
        var currentLocation = CoverageInfo.Location(startLine: 0, startColumn: 0,
                                                    endLine: 0, endColumn: 0)
        var currentCount: UInt64 = 0
        for segment in cValue.segmentsBufPtr {
            if currentCount == 0 {
                if segment.Count != 0 {
                    // start Boundary
                    currentLocation.startLine = segment.Line
                    currentLocation.startColumn = segment.Column
                    currentCount = segment.Count
                }
            } else {
                if segment.Count == 0 {
                    // end Segment
                    currentLocation.endLine = segment.Line
                    currentLocation.endColumn = segment.Column
                    segments[currentLocation] = .init(location: currentLocation,
                                                      count: currentCount)
                    currentLocation = CoverageInfo.Location(startLine: 0, startColumn: 0,
                                                            endLine: 0, endColumn: 0)
                    currentCount = 0
                } else if segment.Count != currentCount {
                    // change Segment
                    if segment.Column > 0 {
                        currentLocation.endLine = segment.Line
                        currentLocation.endColumn = segment.Column - 1
                    } else {
                        currentLocation.endLine = segment.Line - 1
                        currentLocation.endColumn = segment.Column
                    }
                    segments[currentLocation] = .init(location: currentLocation,
                                                      count: currentCount)
                    currentLocation = CoverageInfo.Location(
                        startLine: segment.Line, startColumn: segment.Column,
                        endLine: 0, endColumn: 0
                    )
                    currentCount = segment.Count
                }
            }
        }
        self.segments = segments
    }
}

extension CoverageInfo.File: CustomDebugStringConvertible {
    public var debugDescription: String {
        let segments = self.segments.values
            .map { $0.debugDescription }.joined(separator: "\n\t")
        return "\(name)\n\t\(segments)"
    }
}

extension CoverageInfo.Segment: CustomDebugStringConvertible {
    public var debugDescription: String {
        "\(location) | \(count)"
    }
}

extension CoverageInfo.Location: CustomDebugStringConvertible {
    public var debugDescription: String {
        "\(startLine):\(startColumn) => \(endLine):\(endColumn)"
    }
}

extension CoveredFiles {
    var bufPtr: UnsafeBufferPointer<FileCoverage> {
        UnsafeBufferPointer(start: files, count: files_count)
    }
}

extension FileCoverage {
    var segmentsBufPtr: UnsafeBufferPointer<SegmentCoverage> {
        UnsafeBufferPointer(start: segments, count: segments_count)
    }
}
