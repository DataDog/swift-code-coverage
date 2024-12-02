/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

#include "CCoverageLLVM/CCoverageLLVM.h"
#include <string.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>

static inline const void* _Nullable find_symbol_32bit(const char* _Nonnull symbol,
                                                      const struct mach_header* _Nonnull image,
                                                      intptr_t slide)
{
    struct symtab_command *symtab_cmd = NULL;
    struct segment_command *linkedit_segment = NULL;
    struct segment_command *text_segment = NULL;

    struct segment_command *cur_seg_cmd;
    uintptr_t cur = (uintptr_t)(image + 1); // skip header
    // Iterate through segment commands and find pointers to SYMTAB, LINKEDIT and TEXT segments
    for (uint32_t i = 0; i < image->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (struct segment_command *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_TEXT) == 0) {
                text_segment = cur_seg_cmd;
            } else if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) {
                linkedit_segment = cur_seg_cmd;
            }
        } else if (cur_seg_cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command *)cur_seg_cmd;
        }
    }

    // check that we found them
    if (!symtab_cmd || !linkedit_segment || !text_segment) {
        return NULL;
    }

    // calculate pointers to the symtab list start and symtab text start
    uintptr_t linkedit_base = (uintptr_t)slide + (uintptr_t)(linkedit_segment->vmaddr - linkedit_segment->fileoff);
    struct nlist *symtab = (struct nlist *)(linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);

    struct nlist *sym;
    int index;
    // iterate through symbols and search for our symbol
    for (index = 0, sym = symtab; index < symtab_cmd->nsyms; index += 1, sym += 1) {
        if (sym->n_un.n_strx != 0 && strcmp(symbol, strtab + sym->n_un.n_strx) == 0) {
            // Calculate its address
            uint64_t address = slide + sym->n_value;
            // arm thumb needs first address bit changed
            if (sym->n_desc & N_ARM_THUMB_DEF) {
                return (void *)(address | 1);
            } else {
                return (void *)(address);
            }
        }
    }
    // not found
    return NULL;
}

static inline const void* _Nullable find_symbol_64bit(const char* _Nonnull symbol,
                                                      const struct mach_header_64* _Nonnull image,
                                                      intptr_t slide)
{
    struct symtab_command *symtab_cmd = NULL;
    struct segment_command_64 *linkedit_segment = NULL;
    struct segment_command_64 *text_segment = NULL;

    struct segment_command_64 *cur_seg_cmd;
    uintptr_t cur = (uintptr_t)(image + 1); // skip header
    // Iterate through segment commands and find pointers to SYMTAB, LINKEDIT and TEXT segments
    for (uint32_t i = 0; i < image->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (struct segment_command_64 *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_64) {
            if (strcmp(cur_seg_cmd->segname, SEG_TEXT) == 0) {
                text_segment = cur_seg_cmd;
            } else if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) {
                linkedit_segment = cur_seg_cmd;
            }
        } else if (cur_seg_cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command *)cur_seg_cmd;
        }
    }

    // check that we found them
    if (!symtab_cmd || !linkedit_segment || !text_segment) {
        return NULL;
    }

    // calculate pointers to the symtab list start and symtab text start
    uintptr_t linkedit_base = (uintptr_t)slide + (uintptr_t)(linkedit_segment->vmaddr - linkedit_segment->fileoff);
    struct nlist_64 *symtab = (struct nlist_64 *)(linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);

    struct nlist_64 *sym;
    int index;
    // iterate through symbols and search for our symbol
    for (index = 0, sym = symtab; index < symtab_cmd->nsyms; index += 1, sym += 1) {
        if (sym->n_un.n_strx != 0 && strcmp(symbol, strtab + sym->n_un.n_strx) == 0) {
            // Calculate its address
            uint64_t address = slide + sym->n_value;
            // arm thumb needs first address bit changed
            if (sym->n_desc & N_ARM_THUMB_DEF) {
                return (void *)(address | 1);
            } else {
                return (void *)(address);
            }
        }
    }
    // not found
    return NULL;
}

const void* _Nullable coverage_find_symbol_in_image(const char* _Nonnull symbol,
                                                    const struct mach_header* _Nonnull image,
                                                    intptr_t slide)
{
    if ((image == NULL) || (symbol == NULL)) {
        return NULL;
    }
    return image->magic == MH_MAGIC_64
        ? find_symbol_64bit(symbol, (const struct mach_header_64*)image, slide)
        : find_symbol_32bit(symbol, image, slide);
}
