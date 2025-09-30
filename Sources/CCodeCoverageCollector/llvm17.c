/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2025-Present Datadog, Inc.
 */

#include "CCodeCoverageCollector.h"
#include <string.h>

#pragma mark llvm profile types

// These types and defines are copy-pasted from <llvm/ProfileData/InstrProfData.inc>
// They have to be copied for each new LLVM version. Types can change.

// defines
#define INSTR_PROF_DATA_ALIGNMENT 8
#define VARIANT_MASK_BYTE_COVERAGE (0x1ULL << 60)

typedef void *IntPtrT;

enum InstrProfValueKind : uint32_t {
    #define VALUE_PROF_KIND(Enumerator, Value, Descr) Enumerator = Value,
    
    // These lines are copy-pasted from <llvm/ProfileData/InstrProfData.inc>
    // Search for VALUE_PROF_KIND macro
    
    VALUE_PROF_KIND(IPVK_IndirectCallTarget, 0, "indirect call target")
    VALUE_PROF_KIND(IPVK_MemOPSize, 1, "memory intrinsic functions size")
    VALUE_PROF_KIND(IPVK_First, IPVK_IndirectCallTarget, "first")
    VALUE_PROF_KIND(IPVK_Last, IPVK_MemOPSize, "last")
};

typedef struct __attribute__((aligned(INSTR_PROF_DATA_ALIGNMENT))) __llvm_profile_data {
    #define INSTR_PROF_DATA(Type, LLVMType, Name, Initializer) Type Name;
    
    // These lines are copy-pasted from <llvm/ProfileData/InstrProfData.inc>
    // Search for INSTR_PROF_DATA macro
    
    INSTR_PROF_DATA(const uint64_t, llvm::Type::getInt64Ty(Ctx), NameRef, \
                    ConstantInt::get(llvm::Type::getInt64Ty(Ctx), \
                    IndexedInstrProf::ComputeHash(getPGOFuncNameVarInitializer(Inc->getName()))))
    INSTR_PROF_DATA(const uint64_t, llvm::Type::getInt64Ty(Ctx), FuncHash, \
                    ConstantInt::get(llvm::Type::getInt64Ty(Ctx), \
                    Inc->getHash()->getZExtValue()))
    INSTR_PROF_DATA(const IntPtrT, IntPtrTy, CounterPtr, RelativeCounterPtr)
    INSTR_PROF_DATA(const IntPtrT, llvm::Type::getInt8PtrTy(Ctx), FunctionPointer, \
                    FunctionAddr)
    INSTR_PROF_DATA(IntPtrT, llvm::Type::getInt8PtrTy(Ctx), Values, \
                    ValuesPtrExpr)
    INSTR_PROF_DATA(const uint32_t, llvm::Type::getInt32Ty(Ctx), NumCounters, \
                    ConstantInt::get(llvm::Type::getInt32Ty(Ctx), NumCounters))
    INSTR_PROF_DATA(const uint16_t, Int16ArrayTy, NumValueSites[IPVK_Last+1], \
                    ConstantArray::get(Int16ArrayTy, Int16ArrayVals))
} __llvm_profile_data;

typedef struct ValueProfNode * PtrToNodeT;
typedef struct ValueProfNode {
    #define INSTR_PROF_VALUE_NODE(Type, LLVMType, Name, Initializer) Type Name;
    
    // These lines are copy-pasted from <llvm/ProfileData/InstrProfData.inc>
    // Search for INSTR_PROF_VALUE_NODE macro

    INSTR_PROF_VALUE_NODE(uint64_t, llvm::Type::getInt64Ty(Ctx), Value, \
                          ConstantInt::get(llvm::Type::GetInt64Ty(Ctx), 0))
    INSTR_PROF_VALUE_NODE(uint64_t, llvm::Type::getInt64Ty(Ctx), Count, \
                          ConstantInt::get(llvm::Type::GetInt64Ty(Ctx), 0))
    INSTR_PROF_VALUE_NODE(PtrToNodeT, llvm::Type::getInt8PtrTy(Ctx), Next, \
                          ConstantInt::get(llvm::Type::GetInt8PtrTy(Ctx), 0))
} ValueProfNode;

#pragma mark implementation

void coverage_reset_counters_llvm17(uint64_t profile_version,
                                    const void* _Nonnull func_counters_begin,
                                    const void* _Nonnull func_counters_end,
                                    const void* _Nonnull func_data_begin,
                                    const void* _Nonnull func_data_end)
{
    // convert pointers to the function pointers
    char* const (*llvm_profile_begin_counters_ptr)(void) = func_counters_begin;
    char* const (*llvm_profile_end_counters_ptr)(void) = func_counters_end;
    const __llvm_profile_data* const (*llvm_profile_begin_data)(void) = func_data_begin;
    const __llvm_profile_data* const (*llvm_profile_end_data)(void) = func_data_end;

    // get region of counters data
    char *I = llvm_profile_begin_counters_ptr();
    char *E = llvm_profile_end_counters_ptr();
    // properly select reset value
    char ResetValue = (profile_version & VARIANT_MASK_BYTE_COVERAGE) ? 0xFF : 0;
    // clear it
    memset(I, ResetValue, E - I);

    // iterate over profiling nodes in data
    const __llvm_profile_data *DataBegin = llvm_profile_begin_data();
    const __llvm_profile_data *DataEnd = llvm_profile_end_data();
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
