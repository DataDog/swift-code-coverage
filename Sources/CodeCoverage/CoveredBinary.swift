/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation
import MachO
@_implementationOnly import CCoverageLLVM

public struct CoveredBinary {
    public let name: String
    public let url: URL
    // __llvm_profile_initialize
    let profileInitializeFileFunc: @convention(c) () -> Void
    // __llvm_profile_set_page_size
    let setPageSizeFunc: @convention(c) (UInt) -> Void
    // __llvm_profile_write_file
    let writeFileFunc: @convention(c) () -> Void
    // counters info functions
    let countersFunc: (begin: UnsafeRawPointer, end: UnsafeRawPointer)
    let dataFunc: (begin: UnsafeRawPointer, end: UnsafeRawPointer)
}

public extension CoveredBinary {
    var path: String { url.path }
    
    func initializeProfileFile() {
        profileInitializeFileFunc()
    }
    
    func setPageSize(_ size: UInt) {
        setPageSizeFunc(size)
    }
    
    func write() {
        writeFileFunc()
    }
    
    static var currentProcessBinaries: [CoveredBinary] {
        let numImages = _dyld_image_count()
        var binaries: [CoveredBinary] = []
        binaries.reserveCapacity(Int(numImages))
        for i in 0 ..< numImages {
            guard let header = _dyld_get_image_header(i) else {
                continue
            }
            let url = URL(fileURLWithPath: String(cString: _dyld_get_image_name(i)), isDirectory: false)
            let name = url.lastPathComponent
            let slide = _dyld_get_image_vmaddr_slide(i)
            guard slide != 0 else { continue }
            
            if let pi = findSymbol(named: "___llvm_profile_initialize", image: header, slide: slide),
               let wf = findSymbol(named: "___llvm_profile_write_file", image: header, slide: slide),
               let sp = findSymbol(named: "___llvm_profile_set_page_size", image: header, slide: slide),
               let bc = findSymbol(named: "___llvm_profile_begin_counters", image: header, slide: slide),
               let ec = findSymbol(named: "___llvm_profile_end_counters", image: header, slide: slide),
               let bd = findSymbol(named: "___llvm_profile_begin_data", image: header, slide: slide),
               let ed = findSymbol(named: "___llvm_profile_end_data", image: header, slide: slide)
            {
                binaries.append(CoveredBinary(name: name, url: url,
                                              profileInitializeFileFunc: unsafeBitCast(pi, to: (@convention(c) () -> Void).self),
                                              setPageSizeFunc: unsafeBitCast(sp, to: (@convention(c) (UInt) -> Void).self),
                                              writeFileFunc: unsafeBitCast(wf, to: (@convention(c) () -> Void).self),
                                              countersFunc: (bc, ec), dataFunc: (bd, ed)))
            }
        }
        return binaries
    }
    
    static func findSymbol(named name: String,
                           image header: UnsafePointer<mach_header>,
                           slide: Int) -> UnsafeRawPointer?
    {
        coverage_find_symbol_in_image(name, header, slide)
    }
}

public extension Array where Element == CoveredBinary {
    static var currentProcessBinaries: [CoveredBinary] {
        CoveredBinary.currentProcessBinaries
    }
}
