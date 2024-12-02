/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#pragma once
#include <stdlib.h>
#include <stdbool.h>
#include <mach-o/loader.h>

#if defined(__cplusplus)
#define CC_EXPORT extern "C"
#else
#define CC_EXPORT extern
#endif

//! Project version number for CCoverageLLVM.
CC_EXPORT double CCoverageLLVMVersionNumber;

//! Project version string for CCoverageLLVM.
CC_EXPORT const unsigned char CCoverageLLVMVersionString[];

#if defined(__cplusplus)
extern "C" {
#endif

typedef void* CCoverageProcessor;

// result of constructor call
typedef struct CCoverageProcessorResult {
    bool is_error;
    union {
        CCoverageProcessor _Nullable processor;
        const char* _Nullable error;
    };
} CCoverageProcessorResult;

// This is a copy of LLVM CoverageSegment stucture
typedef struct CCoverageSegment {
    /// The line where this segment begins.
    unsigned int Line;
    /// The column where this segment begins.
    unsigned int Column;
    /// The execution count, or zero if no count was recorded.
    uint64_t Count;
    /// When false, the segment was uninstrumented or skipped.
    bool HasCount;
    /// Whether this enters a new region or returns to a previous count.
    bool IsRegionEntry;
    /// Whether this enters a gap region.
    bool IsGapRegion;
} CCoverageSegment;

// One covered file
typedef struct CCoverageFile {
    const char* _Nonnull name;
    CCoverageSegment* _Nullable segments;
    size_t segments_count;
} CCoverageFile;

// list of files covered in this report
typedef struct CCoverageFiles {
    CCoverageFile* _Nullable files;
    size_t files_count;
} CCoverageFiles;

// coverage parsing command result
typedef struct CCoverageFilesResult {
    bool is_error;
    union {
        CCoverageFiles files;
        const char* _Nullable error;
    };
} CCoverageFilesResult;


struct llvm_coverage_library_exports {
    // create coverage processor object from the binaries
    CCoverageProcessorResult (* _Nonnull init_processor)(const char* _Nonnull const* _Nonnull binaries, uint32_t count);
    // parse profraw file and return file stats
    CCoverageFilesResult (* _Nonnull covered_files)(const CCoverageProcessor _Nonnull processor,
                                                    const char* _Nonnull profraw_file);
    // delete coverage processor object
    void (* _Nonnull destroy_processor)(CCoverageProcessor _Nonnull coverage);
    // reset coverage counters for binary
    void (* _Nonnull reset_counters)(const void* _Nonnull func_counters_begin,
                                     const void* _Nonnull func_counters_end,
                                     const void* _Nonnull func_data_begin,
                                     const void* _Nonnull func_data_end);
};


const void* _Nullable coverage_find_symbol_in_image(const char * _Nonnull symbol,
                                                    const struct mach_header * _Nonnull image,
                                                    intptr_t slide);
#if defined(__cplusplus)
}
#endif
