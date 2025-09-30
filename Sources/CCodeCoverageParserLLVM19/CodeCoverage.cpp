/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#include "CodeCoverage.hpp"
#include "BinaryCoverageReaderRef.hpp"

#include <llvm19/ADT/ArrayRef.h>
#include <llvm19/ProfileData/InstrProfReader.h>
#include <llvm19/ProfileData/InstrProfWriter.h>
#include <llvm19/Support/Errc.h>
#include <llvm19/Support/FileSystem.h>
#include <llvm19/Support/VirtualFileSystem.h>

using namespace llvm;
using namespace coverage;
using namespace llvm19;

CodeCoverage::CodeCoverage(std::vector<std::unique_ptr<llvm::coverage::BinaryCoverageReader>> readers): MappingReaders(std::move(readers)) {
}

// Constructor
Expected<CodeCoverage> CodeCoverage::load(std::vector<StringRef> &Binaries) {
    std::vector<std::unique_ptr<llvm::coverage::BinaryCoverageReader>> MappingReaders;
  
    for (const auto &Binary : Binaries) {
        // Create memory buffer for binary file
        auto CovMappingBufOrErr = MemoryBuffer::getFileOrSTDIN(
            Binary, /*IsText=*/false, /*RequiresNullTerminator=*/false
        );
        // Handle errors
        if (std::error_code EC = CovMappingBufOrErr.getError()) {
            return make_error<StringError>(EC, "Can't read file");
        }
        // Get buffer
        auto CovMappingBuf = CovMappingBufOrErr.get() -> getMemBufferRef();
        SmallVector<std::unique_ptr<MemoryBuffer>, 4> Buffers;
        // Create binary readers for this binary file
        auto CoverageReadersOrErr = BinaryCoverageReader::create(CovMappingBuf, StringRef(), Buffers);
        // handle errors
        if (Error E = CoverageReadersOrErr.takeError()) {
            return std::move(E);
        }
        // save binary readers to the instance
        for (auto &Reader : CoverageReadersOrErr.get()) {
            MappingReaders.push_back(std::move(Reader));
        }
    }
    
    return CodeCoverage(std::move(MappingReaders));
}

// Covert profraw to indexed profile data.
// Method based on `llvm-profdata merge` source code from LLVM tools.
Expected<std::unique_ptr<MemoryBuffer>> CodeCoverage::readProfile(StringRef ProfrawPath) const {
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
    auto FS = llvm::vfs::getRealFileSystem();
    auto ReaderOrErr = InstrProfReader::create(ProfrawPath, *FS);
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
    
    // New feature in LLVM17. Save temporal profile
    if (Reader->hasTemporalProfile()) {
        auto &Traces = Reader->getTemporalProfTraces();
        if (!Traces.empty()) {
            Writer.addTemporalProfileTraces(Traces, Reader->getTemporalProfTraceStreamSize());
        }
    }
    
    // Handle reader errors. Could happen in the iteration
    if (Reader->hasError()) {
        if (Error E = Reader->getError()) {
            return std::move(E);
        }
    }
    
    // Apple LLVM 17 has VTable symbols but by default flag is false and can be ignored
    // New feature in LLVM17. Save binary ids
    std::vector<llvm::object::BuildID> BinaryIds;
    if (Error E = Reader->readBinaryIds(BinaryIds)) {
        return std::move(E);
    }
    Writer.addBinaryIds(BinaryIds);

    // Write indexed data to the buffer and return
    return Writer.writeBuffer();
}

// Convert file coverage to the C structure so it can be sent to the Swift
CCoverageFile CodeCoverage::processFile(StringRef Name, CoverageMapping &Coverage) const {
    auto CoverageForFile = Coverage.getCoverageForFile(Name);
    
    char* NameStr = new char[Name.size()+1];
    memcpy(NameStr, Name.data(), Name.size());
    NameStr[Name.size()] = '\0';
    
    auto Count = std::distance(CoverageForFile.begin(), CoverageForFile.end());
    if (Count == 0) {
        return CCoverageFile({ NameStr, nullptr, 0 });
    }
    
    CCoverageSegment* Segments = new CCoverageSegment[Count];
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
    
    return CCoverageFile({ NameStr, Segments, size_t(Count) });
}

// Calculate coverage for profraw file
// Based on `llvm-cov show` source code from LLVM tools.
Expected<CCoverageFiles> CodeCoverage::coverage(StringRef ProfrawPath) const {
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
    
    // We are using methods from our patch so we can reuse readers.
    // We will create Ref classes for the real readers so we can iterate
    // in the different threads at the same time.
    std::vector<std::unique_ptr<CoverageMappingReader>> Readers;
    Readers.reserve(MappingReaders.size());
    
    for (auto &Reader: MappingReaders) {
        Readers.push_back(
            std::unique_ptr<CoverageMappingReader>(
                new BinaryCoverageReaderRef(Reader.get())
            )
        );
    }
    
    // create coverage mapping from resetted readers and profile
    auto CoverageOrErr = CoverageMapping::load(ArrayRef(Readers), *ProfileReader);
    
    // handle errors
    if (Error E = CoverageOrErr.takeError()) {
        return std::move(E);
    }
    auto Coverage = std::move(CoverageOrErr.get());
    
    // Convert report to the C structures
    auto Files = Coverage->getUniqueSourceFiles();
    if (Files.size() == 0) {
        return CCoverageFiles({ nullptr, 0 });
    }
    CCoverageFile *CoverageFiles = new CCoverageFile[Files.size()];
    for (size_t Current = 0; Current < Files.size(); Current++) {
        CoverageFiles[Current] = processFile(Files[Current], *Coverage);
    }
    return CCoverageFiles({ CoverageFiles, Files.size() });
}
