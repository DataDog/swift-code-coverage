/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#include "CodeCoverage.hpp"
#include <sstream>

#include "llvm17/ADT/ArrayRef.h"
#include "llvm17/ProfileData/InstrProfReader.h"
#include "llvm17/ProfileData/InstrProfWriter.h"
#include "llvm17/Support/Errc.h"
#include "llvm17/Support/FileSystem.h"
#include "llvm17/Support/VirtualFileSystem.h"

using namespace llvm;
using namespace coverage;
using namespace llvm17;

Expected<CodeCoverage*> CodeCoverage::load(std::vector<StringRef> &Binaries) {
    CodeCoverage* Coverage = new CodeCoverage();
    
    for (const auto &Binary : Binaries) {
        auto CovMappingBufOrErr = MemoryBuffer::getFileOrSTDIN(
            Binary, /*IsText=*/false, /*RequiresNullTerminator=*/false
        );
        if (std::error_code EC = CovMappingBufOrErr.getError()) {
            delete Coverage;
            return make_error<StringError>(EC, "Can't read file");
        }
        auto CovMappingBuf = std::move(CovMappingBufOrErr.get());
        SmallVector<std::unique_ptr<MemoryBuffer>, 4> Buffers;
        auto CoverageReadersOrErr = BinaryCoverageReader::create(
            CovMappingBuf->getMemBufferRef(), StringRef(), Buffers
        );
        if (Error E = CoverageReadersOrErr.takeError()) {
            delete Coverage;
            return std::move(E);
        }
        for (auto &Reader : CoverageReadersOrErr.get()) {
            Coverage->MappingReaders.push_back(std::move(Reader));
        }
    }
    
    return Coverage;
}

Expected<std::unique_ptr<MemoryBuffer>> CodeCoverage::readProfile(StringRef ProfrawPath) {
    sys::fs::file_status Status;
    sys::fs::status(ProfrawPath, Status);
    if (!sys::fs::exists(Status)) {
        return make_error<StringError>(make_error_code(errc::no_such_file_or_directory),
                                       "File not found");
    }
    if (!llvm::sys::fs::is_regular_file(Status)) {
        return make_error<StringError>(make_error_code(errc::is_a_directory),
                                       "Expected file, not the directory");
    }
    
    auto FS = llvm::vfs::getRealFileSystem();
    auto ReaderOrErr = InstrProfReader::create(ProfrawPath, *FS);
    if (Error E = ReaderOrErr.takeError()) {
        return std::move(E);
    }

    auto Reader = std::move(ReaderOrErr.get());
    
    InstrProfWriter Writer(/*sparse*/ true);
    
    if (Error E = Writer.mergeProfileKind(Reader->getProfileKind())) {
        return std::move(E);
    }
    
    std::optional<Error> WriteError;
    for (auto &I : *Reader) {
        Writer.addRecord(std::move(I), [&](Error E) {
            WriteError = std::move(E);
        });
        if (WriteError.has_value()) {
            return std::move(*WriteError);
        }
    }
    
    if (Reader->hasTemporalProfile()) {
        auto &Traces = Reader->getTemporalProfTraces();
        if (!Traces.empty()) {
            Writer.addTemporalProfileTraces(Traces, Reader->getTemporalProfTraceStreamSize());
        }
    }
    
    if (Reader->hasError()) {
        if (Error E = Reader->getError()) {
            return std::move(E);
        }
    }
    
    std::vector<llvm::object::BuildID> BinaryIds;
    if (Error E = Reader->readBinaryIds(BinaryIds)) {
        return std::move(E);
    }
    Writer.addBinaryIds(BinaryIds);

    return Writer.writeBuffer();
}

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

Expected<CoveredFiles> CodeCoverage::coverage(StringRef ProfrawPath) {
    auto ProfileBufferOrErr = readProfile(ProfrawPath);
    if (Error E = ProfileBufferOrErr.takeError()) {
        return std::move(E);
    }
    auto ProfileBuffer = std::move(ProfileBufferOrErr.get());
    
    auto ProfileReaderOrErr = IndexedInstrProfReader::create(std::move(ProfileBuffer));
    if (Error E = ProfileReaderOrErr.takeError()) {
        return std::move(E);
    }
    auto ProfileReader = std::move(ProfileReaderOrErr.get());
    
    MappingReadersLock.lock();
    for (auto &Reader: MappingReaders) {
        reinterpret_cast<BinaryCoverageReader*>(Reader.get())->reset();
    }
    
    auto CoverageOrErr = CoverageMapping::load(ArrayRef(MappingReaders), *ProfileReader);
    MappingReadersLock.unlock();
    if (Error E = CoverageOrErr.takeError()) {
        return std::move(E);
    }
    auto Coverage = std::move(CoverageOrErr.get());
    
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
