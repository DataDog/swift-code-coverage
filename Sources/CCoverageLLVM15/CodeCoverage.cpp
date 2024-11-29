/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#include "CodeCoverage.hpp"
#include <sstream>

#include "llvm15/ADT/ArrayRef.h"
#include "llvm15/ProfileData/InstrProfReader.h"
#include "llvm15/ProfileData/InstrProfWriter.h"
#include "llvm15/Support/Errc.h"
#include "llvm15/Support/FileSystem.h"

#include <iostream>

using namespace llvm;
using namespace coverage;
using namespace llvm15;

// Constructor
Expected<CodeCoverage*> CodeCoverage::load(std::vector<StringRef> &Binaries) {
    CodeCoverage* Coverage = new CodeCoverage();
    
    for (const auto &Binary : llvm::enumerate(Binaries)) {
        // Create memory buffer for binary file
        auto CovMappingBufOrErr = MemoryBuffer::getFileOrSTDIN(
            Binary.value(), /*IsText=*/false, /*RequiresNullTerminator=*/false
        );
        // Handle errors
        if (std::error_code EC = CovMappingBufOrErr.getError()) {
            delete Coverage;
            return make_error<StringError>(EC, "Can't read file");
        }
        // Get buffer
        MemoryBufferRef CovMappingBufRef = CovMappingBufOrErr.get()->getMemBufferRef();
        SmallVector<std::unique_ptr<MemoryBuffer>, 4> Buffers;
        // Create binary readers for this binary file
        auto CoverageReadersOrErr = BinaryCoverageReader::create(CovMappingBufRef, StringRef(), Buffers);
        // handle errors
        if (Error E = CoverageReadersOrErr.takeError()) {
            delete Coverage;
            return std::move(E);
        }
        // save binary readers to the instance
        for (auto &Reader : CoverageReadersOrErr.get()) {
            Coverage->MappingReaders.push_back(std::move(Reader));
        }
    }
    
    return Coverage;
}

// Covert profraw to indexed profile data.
// Method based on `llvm-profdata merge` source code from LLVM tools.
Expected<std::unique_ptr<MemoryBuffer>> CodeCoverage::readProfile(StringRef ProfrawPath) {
    sys::fs::file_status Status;
    // get status for file
    sys::fs::status(ProfrawPath, Status);
    // check file is good
    if (!sys::fs::exists(Status)) {
        return make_error<StringError>(make_error_code(errc::no_such_file_or_directory),
                                       "File not found");
    }
    if (!llvm::sys::fs::is_regular_file(Status)) {
        return make_error<StringError>(make_error_code(errc::is_a_directory),
                                       "Expected file, not the directory");
    }
    
    // Create reader for file
    auto ReaderOrErr = InstrProfReader::create(ProfrawPath);
    if (Error E = ReaderOrErr.takeError()) {
        return std::move(E);
    }

    auto Reader = std::move(ReaderOrErr.get());
    
    // Create writer
    InstrProfWriter Writer(/*sparse*/ true);
    
    // Set writer type
    if (Error E = Writer.mergeProfileKind(Reader->getProfileKind())) {
        return std::move(E);
    }
    
    // Write records from the Reader to the Writer
    std::optional<Error> WriteError;
    for (auto &I : *Reader) {
        Writer.addRecord(std::move(I), [&](Error E) {
            WriteError = std::move(E);
        });
        // Handle write error
        if (WriteError.has_value()) {
            return std::move(*WriteError);
        }
    }
    
    // Handle reader errors. Could happen in the iteration
    if (Reader->hasError()) {
        if (Error E = Reader->getError()) {
            return std::move(E);
        }
    }

    // Write indexed data to the buffer and return
    return Writer.writeBuffer();
}

// Convert file coverage to the C structure so it can be sent to the Swift
FileCoverage CodeCoverage::processFile(StringRef Name, CoverageMapping &Coverage) {
    auto CoverageForFile = Coverage.getCoverageForFile(Name);
    
    char* NameStr = new char[Name.size()+1];
    memcpy(NameStr, Name.data(), Name.size());
    NameStr[Name.size()] = '\0';
    
    auto Count = std::distance(CoverageForFile.begin(), CoverageForFile.end());
    if (Count == 0) {
        return FileCoverage({ NameStr, nullptr, 0 });
    }
    
    SegmentCoverage* Segments = new SegmentCoverage[Count];
    size_t CurrentSegment = 0;
    for (const auto &Segment: CoverageForFile) {
        Segments[CurrentSegment] = {
            .Line = Segment.Line,
            .Column = Segment.Col,
            .Count = Segment.Count,
            .HasCount = Segment.HasCount,
            .IsRegionEntry = Segment.IsRegionEntry,
            .IsGapRegion = Segment.IsGapRegion
        };
        CurrentSegment++;
    }
    
    return FileCoverage({ NameStr, Segments, size_t(Count) });
}

// Calculate coverage for profraw file
// Based on `llvm-cov show` source code from LLVM tools.
Expected<CoveredFiles> CodeCoverage::coverage(StringRef ProfrawPath) {
    // Read profraw and get profdata buffer.
    auto ProfileBufferOrErr = readProfile(ProfrawPath);
    if (Error E = ProfileBufferOrErr.takeError()) {
        return std::move(E);
    }
    auto ProfileBuffer = std::move(ProfileBufferOrErr.get());
    
    // Create indexed reader for profdata buffer
    auto ProfileReaderOrErr = IndexedInstrProfReader::create(std::move(ProfileBuffer));
    if (Error E = ProfileReaderOrErr.takeError()) {
        return std::move(E);
    }
    auto ProfileReader = std::move(ProfileReaderOrErr.get());
    
    // BinaryCoverageReader isn't thread safe. We have to lock.
    MappingReadersLock.lock();
    // We are using method from our patch so we can reuse readers.
    // dynamic_cast can't be used because of lack of RTTI.
    // it's safe because LLVM version is locked
    // and we know that BinaryCoverageReader inherited directly from base class.
    for (auto &Reader: MappingReaders) {
        reinterpret_cast<BinaryCoverageReader*>(Reader.get())->reset();
    }
    
    // create coverage mapping from resetted readers and profile
    auto CoverageOrErr = CoverageMapping::load(ArrayRef(MappingReaders), *ProfileReader);
    // unlock
    MappingReadersLock.unlock();
    // handle errors
    if (Error E = CoverageOrErr.takeError()) {
        return std::move(E);
    }
    auto Coverage = std::move(CoverageOrErr.get());
    
    // Convert report to the C structures
    auto Files = Coverage->getUniqueSourceFiles();
    if (Files.size() == 0) {
        return CoveredFiles({ nullptr, 0 });
    }
    FileCoverage *CoverageFiles = new FileCoverage[Files.size()];
    for (size_t Current = 0; Current < Files.size(); Current++) {
        CoverageFiles[Current] = processFile(Files[Current], *Coverage);
    }
    return CoveredFiles({ CoverageFiles, Files.size() });
}
