/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#pragma once
#include <stdlib.h>
#include <stdbool.h>
#include <mach-o/loader.h>

#if defined(__cplusplus)
#define CC_EXPORT extern "C"
#else
#define CC_EXPORT extern
#endif

/// find symbol in image by name
CC_EXPORT const void* _Nullable coverage_find_symbol_in_image(const char * _Nonnull symbol,
                                                              const struct mach_header * _Nonnull image,
                                                              intptr_t slide);

/// reset coverage counters for binary, LLVM 17. Swift 6.0..<6.1
CC_EXPORT void coverage_reset_counters_llvm17(uint64_t profile_version,
                                              const void* _Nonnull func_counters_begin,
                                              const void* _Nonnull func_counters_end,
                                              const void* _Nonnull func_data_begin,
                                              const void* _Nonnull func_data_end);

/// reset coverage counters for binary, LLVM 19 Swift 6.1...6.2+
CC_EXPORT void coverage_reset_counters_llvm19(uint64_t profile_version,
                                              const void* _Nonnull func_counters_begin,
                                              const void* _Nonnull func_counters_end,
                                              const void* _Nonnull func_data_begin,
                                              const void* _Nonnull func_data_end,
                                              const void* _Nonnull func_bitmap_begin,
                                              const void* _Nonnull func_bitmap_end);
