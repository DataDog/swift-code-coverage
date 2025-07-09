/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#pragma once
#include <CCoverageLLVM/CCoverageLLVM.h>
#include <llvm16/ProfileData/Coverage/CoverageMapping.h>
#include <llvm16/ProfileData/Coverage/CoverageMappingReader.h>
#include <llvm16/Support/MemoryBuffer.h>

namespace llvm16 {

/// The implementation of the coverage tool.
class CodeCoverage {
public:
    static llvm::Expected<CodeCoverage*> load(std::vector<llvm::StringRef> &Binaries);
    llvm::Expected<CCoverageFiles> coverage(llvm::StringRef ProfrawPath);
private:
    CodeCoverage() {};
    std::vector<std::unique_ptr<llvm::coverage::BinaryCoverageReader>> MappingReaders;
    llvm::Expected<std::unique_ptr<llvm::MemoryBuffer>> readProfile(llvm::StringRef ProfrawPath);
    CCoverageFile processFile(llvm::StringRef Name, llvm::coverage::CoverageMapping &Coverage);
};

}
