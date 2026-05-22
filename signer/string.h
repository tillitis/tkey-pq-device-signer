// SPDX-FileCopyrightText: 2025 Tillitis AB <tillitis.se>
// SPDX-License-Identifier: GPL-2.0-only

#ifndef STRING_H
#define STRING_H

#include <stddef.h>

/* Provided by tkey-libs libcommon.a */
void *memcpy(void *dest, const void *src, size_t n);
void *memset(void *s, int c, size_t n);

/* Not in tkey-libs — use compiler builtins */
static inline void *memmove(void *dest, const void *src, size_t n)
{
    return __builtin_memmove(dest, src, n);
}

static inline int memcmp(const void *s1, const void *s2, size_t n)
{
    return __builtin_memcmp(s1, s2, n);
}

#endif