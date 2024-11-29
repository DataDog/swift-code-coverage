/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#pragma once
#include <CCoverageLLVM/CCoverageLLVM.h>

//! Project version number for CCoverageLLVM15.
CC_EXPORT double CCoverageLLVM15VersionNumber;

//! Project version string for CCoverageLLVM15.
CC_EXPORT const unsigned char CCoverageLLVM15VersionString[];

// Main library export
CC_EXPORT struct llvm_coverage_library_exports llvm15_coverage_library_exports;
