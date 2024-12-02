/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#include "Coverage.h"
#include "ResetCounters.hpp"
#include "CodeCoverage.hpp"

using namespace llvm;
using namespace llvm17;

static const char* errorMessage(Error E) {
    auto str = toString(std::move(E));
    char* cstr = new char[str.size() + 1];
    memcpy(cstr, str.data(), str.size());
    cstr[str.size()] = '\0';
    return cstr;
}

// C wrapper for load() method
static CCoverageProcessorResult e_init_processor(const char* const* binaries, uint32_t count) {
    std::vector<StringRef> sbinaries;
    sbinaries.reserve(count);
    for (const auto &binary: ArrayRef<const char*>(binaries, count)) {
        sbinaries.push_back(binary);
    }
    auto processor = CodeCoverage::load(sbinaries);
    if (Error E = processor.takeError()) {
        return CCoverageProcessorResult({
            .is_error = true,
            .error = errorMessage(std::move(E))
        });
    }
    return CCoverageProcessorResult({.is_error = false, .processor = processor.get()});
}

// C wrapper for coverage() method
static CCoverageFilesResult e_covered_files(const CCoverageProcessor processor,
                                            const char* profraw_file)
{
    
    auto CoverageProcessor = static_cast<CodeCoverage*>(processor);
    auto CoverageOrErr = CoverageProcessor->coverage(profraw_file);
    
    if (Error E = CoverageOrErr.takeError()) {
        return CCoverageFilesResult({
            .is_error = true,
            .error = errorMessage(std::move(E))
        });
    }
    
    return CCoverageFilesResult({.is_error = false, .files = CoverageOrErr.get()});
}

// C wrapper for delete
static void e_destroy_processor(CCoverageProcessor coverage) {
    delete static_cast<CodeCoverage*>(coverage);
}

// Export pointers for all functions in the structure
// It's simpler to dynamically load it this way
// Note that it prefixed with llvm version, so two llvm libs could be loaded at the same time
struct llvm_coverage_library_exports llvm17_coverage_library_exports = {
    .init_processor = &e_init_processor,
    .covered_files = &e_covered_files,
    .destroy_processor = &e_destroy_processor,
    .reset_counters = &llvm17::reset_counters
};
