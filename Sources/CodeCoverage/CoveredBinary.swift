/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation
import CCoverageLLVM
import MachO

public struct CoveredBinary {
    let name: String
    let path: String
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
            let path = String(cString: _dyld_get_image_name(i))
            let name = URL(fileURLWithPath: path).lastPathComponent
            let slide = _dyld_get_image_vmaddr_slide(i)
            guard slide != 0 else { continue }
            
            if let pi = llvm_coverage_find_symbol_in_image("___llvm_profile_initialize", header, slide),
               let wf = llvm_coverage_find_symbol_in_image("___llvm_profile_write_file", header, slide),
               let sp = llvm_coverage_find_symbol_in_image("___llvm_profile_set_page_size", header, slide),
               let bc = llvm_coverage_find_symbol_in_image("___llvm_profile_begin_counters", header, slide),
               let ec = llvm_coverage_find_symbol_in_image("___llvm_profile_end_counters", header, slide),
               let bd = llvm_coverage_find_symbol_in_image("___llvm_profile_begin_data", header, slide),
               let ed = llvm_coverage_find_symbol_in_image("___llvm_profile_end_data", header, slide)
            {
                binaries.append(CoveredBinary(name: name, path: path,
                                              profileInitializeFileFunc: unsafeBitCast(pi, to: (@convention(c) () -> Void).self),
                                              setPageSizeFunc: unsafeBitCast(sp, to: (@convention(c) (UInt) -> Void).self),
                                              writeFileFunc: unsafeBitCast(wf, to: (@convention(c) () -> Void).self),
                                              countersFunc: (bc, ec), dataFunc: (bd, ed)))
            }
        }
        return binaries
    }
}

public extension Array where Element == CoveredBinary {
    static var currentProcessBinaries: [CoveredBinary] {
        CoveredBinary.currentProcessBinaries
    }
}
