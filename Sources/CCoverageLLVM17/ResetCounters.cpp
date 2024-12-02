/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#include "ResetCounters.hpp"
#include <llvm17/ProfileData/InstrProf.h>

using namespace llvm;

typedef void *IntPtrT;

typedef struct __attribute__((aligned(INSTR_PROF_DATA_ALIGNMENT))) __llvm_profile_data {
#define INSTR_PROF_DATA(Type, LLVMType, Name, Initializer) Type Name;
#include <llvm17/ProfileData/InstrProfData.inc>
} __llvm_profile_data;

typedef struct ValueProfNode * PtrToNodeT;
typedef struct ValueProfNode {
#define INSTR_PROF_VALUE_NODE(Type, LLVMType, Name, Initializer) Type Name;
#include <llvm17/ProfileData/InstrProfData.inc>
} ValueProfNode;

void llvm17::reset_counters(const void* func_counters_begin,
                            const void* func_counters_end,
                            const void* func_data_begin,
                            const void* func_data_end)
{
    // convert pointers to the function pointers
    auto llvm_profile_begin_counters_ptr = reinterpret_cast<char*(*)()>(const_cast<void*>(func_counters_begin));
    auto llvm_profile_end_counters_ptr = reinterpret_cast<char*(*)()>(const_cast<void*>(func_counters_end));
    auto llvm_profile_begin_data = reinterpret_cast<const __llvm_profile_data*(*)()>(const_cast<void*>(func_data_begin));
    auto llvm_profile_end_data = reinterpret_cast<const __llvm_profile_data*(*)()>(const_cast<void*>(func_data_end));

    // get region of counters data
    char *I = (*llvm_profile_begin_counters_ptr)();
    char *E = (*llvm_profile_end_counters_ptr)();
    // clear it
    memset(I, 0x0, E - I);

    // iterate over profiling nodes in data
    const __llvm_profile_data *DataBegin = (*llvm_profile_begin_data)();
    const __llvm_profile_data *DataEnd = (*llvm_profile_end_data)();
    const __llvm_profile_data *DI;
    for (DI = DataBegin; DI < DataEnd; ++DI) {
        uint64_t CurrentVSiteCount = 0;
        uint32_t VKI, i;
        if (!DI->Values) {
            continue;
        }

        // Get values for this profiling node
        ValueProfNode **ValueCounters = (ValueProfNode **)DI->Values;

        // Check all types of counters (iterate over enum)
        // and gather amount of values
        for (VKI = IPVK_First; VKI <= IPVK_Last; ++VKI) {
            CurrentVSiteCount += DI->NumValueSites[VKI];
        }

        // iterate through counters
        // this is an array of linked lists
        for (i = 0; i < CurrentVSiteCount; ++i) {
            // get list
            ValueProfNode *CurrentVNode = ValueCounters[i];

            // clear all counters in the list
            while (CurrentVNode) {
                CurrentVNode->Count = 0;
                CurrentVNode = CurrentVNode->Next;
            }
        }
    }
}
