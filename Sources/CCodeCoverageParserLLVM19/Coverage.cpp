/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#include <CCodeCoverageParser/CCodeCoverageParser.h>
#include "CodeCoverage.hpp"

using namespace llvm;
using namespace llvm19;

extern "C" {
    struct CCoverageParserLLMV19 {
        struct CCoverageParser super;
        CodeCoverage coverage;
        
        CCoverageParserLLMV19(CodeCoverage c, struct CCoverageParser s): coverage(std::move(c)), super(s) {}
    };
}

static char* copyString(const char* str, size_t len) {
    char* cstr = new char[len+1];
    memmove(cstr, str, len);
    cstr[len] = '\0';
    return cstr;
}

static const char* errorMessage(Error E) {
    auto str = toString(std::move(E));
    return copyString(str.data(), str.size());
}

// C wrapper for coverage() method
LLVM_ATTRIBUTE_NOINLINE
static CCoverageFilesResult cp_covered_files(const struct CCoverageParser* self,
                                             const char* profraw_file)
{
    
    auto sself = reinterpret_cast<const struct CCoverageParserLLMV19*>(self);
    auto CoverageOrErr = sself->coverage.coverage(profraw_file);
    
    if (Error E = CoverageOrErr.takeError()) {
        return CCoverageFilesResult({
            .is_error = true,
            .error = errorMessage(std::move(E))
        });
    }
    
    return CCoverageFilesResult({.is_error = false, .files = CoverageOrErr.get()});
}

// C wrapper for delete
LLVM_ATTRIBUTE_NOINLINE
static void cp_destroy(struct CCoverageParser* self) {
    delete reinterpret_cast<struct CCoverageParserLLMV19*>(self);
}


LLVM_ATTRIBUTE_NOINLINE
CCoverageParserResult cl_create_processor(const char* _Nonnull const* _Nonnull binaries, uint32_t count) {
    std::vector<StringRef> sbinaries;
    sbinaries.reserve(count);
    for (const auto &binary: ArrayRef<const char*>(binaries, count)) {
        sbinaries.push_back(binary);
    }
    auto coverage = CodeCoverage::load(sbinaries);
    if (Error E = coverage.takeError()) {
        return CCoverageParserResult({
            .is_error = true,
            .error = errorMessage(std::move(E))
        });
    }
    
    /// Export pointers for all functions in the structure
    /// It's simpler to use them in the Swift this way
    /// It will work like the object
    CCoverageParser super;
    super.covered_files = &cp_covered_files;
    super.destroy = &cp_destroy;
    auto processor = new CCoverageParserLLMV19(std::move(coverage.get()), super);
    
    return CCoverageParserResult({
        .is_error = false,
        .parser = reinterpret_cast<struct CCoverageParser*>(processor)
    });
}

const struct CCoverageParserLibrary coverage_parser_library_instance = {
    .llvm_version = LLVM_VERSION_STRING,
    .create_parser = &cl_create_processor
};
