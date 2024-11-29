/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#pragma once

namespace llvm17 {
void reset_counters(const void* _Nonnull func_counters_begin,
                    const void* _Nonnull func_counters_end,
                    const void* _Nonnull func_data_begin,
                    const void* _Nonnull func_data_end);
}
