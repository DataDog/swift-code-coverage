/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#pragma once
#include <CCoverageLLVM/CCoverageLLVM.h>

//! Project version number for CCoverageLLVM17.
CC_EXPORT double CCoverageLLVM17VersionNumber;

//! Project version string for CCoverageLLVM17.
CC_EXPORT const unsigned char CCoverageLLVM17VersionString[];

// Main library export
CC_EXPORT struct llvm_coverage_library_exports llvm17_coverage_library_exports;
