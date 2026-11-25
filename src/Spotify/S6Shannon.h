// Shannon stream cipher with MAC (Greg Rose, Qualcomm; public domain reference design), as Spotify's access point
// protocol uses it: one instance per direction, re-keyed with a 32-bit big-endian packet counter as the nonce
// before every packet, a 4-byte MAC after it.
#ifndef S6SHANNON_H
#define S6SHANNON_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint32_t R[16];
    uint32_t CRC[16];
    uint32_t initR[16];
    uint32_t konst;
    uint32_t sbuf;
    uint32_t mbuf;
    int nbuf;
} S6Shannon;

void s6_shannon_key(S6Shannon *c, const uint8_t *key, size_t keylen);
void s6_shannon_nonce(S6Shannon *c, const uint8_t *nonce, size_t noncelen);
void s6_shannon_nonce_u32(S6Shannon *c, uint32_t n);
void s6_shannon_encrypt(S6Shannon *c, uint8_t *buf, size_t nbytes);
void s6_shannon_decrypt(S6Shannon *c, uint8_t *buf, size_t nbytes);
void s6_shannon_finish(S6Shannon *c, uint8_t *mac, size_t nbytes);

#endif
