/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#include "BinaryCoverageReaderRef.hpp"

using namespace llvm16;
using namespace llvm;
using namespace coverage;

BinaryCoverageReaderRef::BinaryCoverageReaderRef(BinaryCoverageReader *Reader):
    Filenames(Reader->getFilenamesRef()),
    MappingRecords(Reader->getMappingRecordsRef()) {;}

// Copied from BinaryCoverageReader::readNextRecord
Error BinaryCoverageReaderRef::readNextRecord(CoverageMappingRecord &Record) {
    if (CurrentRecord >= MappingRecords.size())
        return make_error<CoverageMapError>(coveragemap_error::eof);

    FunctionsFilenames.clear();
    Expressions.clear();
    MappingRegions.clear();
    auto &R = MappingRecords[CurrentRecord];
    auto F = Filenames.slice(R.FilenamesBegin, R.FilenamesSize);
    RawCoverageMappingReader Reader(R.CoverageMapping, F, FunctionsFilenames,
                                    Expressions, MappingRegions);
    if (auto Err = Reader.read())
        return Err;

    Record.FunctionName = R.FunctionName;
    Record.FunctionHash = R.FunctionHash;
    Record.Filenames = FunctionsFilenames;
    Record.Expressions = Expressions;
    Record.MappingRegions = MappingRegions;

    ++CurrentRecord;
    return Error::success();
}
