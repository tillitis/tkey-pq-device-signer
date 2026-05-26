// SPDX-FileCopyrightText: 2025 Tillitis AB <tillitis.se>
// SPDX-License-Identifier: GPL-2.0-only

#ifndef STRING_H
#define STRING_H

#include <stddef.h>
#include <stdint.h>

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
    const uint8_t *pa = (const uint8_t *)s1;
    const uint8_t *pb = (const uint8_t *)s2;
    uint8_t diff = 0;

    for (size_t i = 0; i < n; i++) {
        diff |= pa[i] ^ pb[i];
    }

    return diff == 0;
}

#endif