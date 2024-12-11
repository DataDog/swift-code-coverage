/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#pragma once
#include <llvm17/ProfileData/Coverage/CoverageMappingReader.h>

namespace llvm17 {

class BinaryCoverageReaderRef: public llvm::coverage::CoverageMappingReader {
private:
    size_t CurrentRecord = 0;
    llvm::ArrayRef<std::string> Filenames;
    llvm::ArrayRef<llvm::coverage::BinaryCoverageReader::ProfileMappingRecord> MappingRecords;
    std::vector<llvm::StringRef> FunctionsFilenames;
    std::vector<llvm::coverage::CounterExpression> Expressions;
    std::vector<llvm::coverage::CounterMappingRegion> MappingRegions;
public:
    BinaryCoverageReaderRef(llvm::coverage::BinaryCoverageReader *Reader);
    llvm::Error readNextRecord(llvm::coverage::CoverageMappingRecord &Record) override;
};

}
