/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#pragma once
#include <stdlib.h>
#include <stdbool.h>

#if defined(__cplusplus)
#define CC_EXPORT extern "C"
#else
#define CC_EXPORT extern
#endif

#if defined(__cplusplus)
extern "C" {
#endif

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

struct CCoverageParser {
    // parse profraw file and return file stats
    CCoverageFilesResult (* _Nonnull covered_files)(const struct CCoverageParser* _Nonnull self,
                                                    const char* _Nonnull profraw_file);
    // delete coverage processor object
    void (* _Nonnull destroy)(struct CCoverageParser* _Nonnull self);
};

// result of constructor call
typedef struct CCoverageParserResult {
    bool is_error;
    union {
        struct CCoverageParser* _Nullable parser;
        const char* _Nullable error;
    };
} CCoverageParserResult;

// Plugin exports type.
struct CCoverageParserLibrary {
    // processor's llvm version
    const char* _Nonnull llvm_version;
    // Creates new proccessor instance
    CCoverageParserResult (* _Nonnull create_parser)(const char* _Nonnull const* _Nonnull binaries, uint32_t count);
};

#if defined(__cplusplus)
}
#endif

// Plugin entry point. Should be created inside the plugins.
CC_EXPORT const struct CCoverageParserLibrary coverage_parser_library_instance;
