// Shannon stream cipher (Greg Rose, Qualcomm Australia, 2003). Written after the public reference design and
// librespot's use of it; words are little endian, the per-packet nonce big endian.
#include "S6Shannon.h"
#include <string.h>

#define N 16
#define FOLD N
#define INITKONST 0x6996c53aU
#define KEYP 13

static inline uint32_t rotl(uint32_t w, int x) { return (w << x) | (w >> (32 - x)); }

static inline uint32_t sbox1(uint32_t w)
{
    w ^= rotl(w, 5) | rotl(w, 7);
    w ^= rotl(w, 19) | rotl(w, 22);
    return w;
}

static inline uint32_t sbox2(uint32_t w)
{
    w ^= rotl(w, 7) | rotl(w, 22);
    w ^= rotl(w, 5) | rotl(w, 19);
    return w;
}

static inline uint32_t le32(const uint8_t *b)
{
    return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

static inline void put_le32(uint8_t *b, uint32_t w)
{
    b[0] = (uint8_t)w; b[1] = (uint8_t)(w >> 8); b[2] = (uint8_t)(w >> 16); b[3] = (uint8_t)(w >> 24);
}

static void cycle(S6Shannon *c)
{
    uint32_t t = c->R[12] ^ c->R[13] ^ c->konst;
    t = sbox1(t) ^ rotl(c->R[0], 1);
    for (int i = 1; i < N; i++) c->R[i - 1] = c->R[i];
    c->R[N - 1] = t;
    t = sbox2(c->R[2] ^ c->R[15]);
    c->R[0] ^= t;
    c->sbuf = t ^ c->R[8] ^ c->R[12];
}

// 32 parallel CRC-16s (x^16 + x^15 + x^2 + 1) of the input words, fed into the MAC at the end
static void crcfunc(S6Shannon *c, uint32_t i)
{
    uint32_t t = c->CRC[0] ^ c->CRC[2] ^ c->CRC[15] ^ i;
    for (int j = 1; j < N; j++) c->CRC[j - 1] = c->CRC[j];
    c->CRC[N - 1] = t;
}

static void macfunc(S6Shannon *c, uint32_t i)
{
    crcfunc(c, i);
    c->R[KEYP] ^= i;
}

static void diffuse(S6Shannon *c)
{
    for (int i = 0; i < FOLD; i++) cycle(c);
}

static void loadkey(S6Shannon *c, const uint8_t *key, size_t keylen)
{
    size_t i = 0;
    for (; i + 4 <= keylen; i += 4) {
        c->R[KEYP] ^= le32(key + i);
        cycle(c);
    }
    if (i < keylen) {
        uint8_t xtra[4] = { 0, 0, 0, 0 };
        memcpy(xtra, key + i, keylen - i);
        c->R[KEYP] ^= le32(xtra);
        cycle(c);
    }
    c->R[KEYP] ^= (uint32_t)keylen;
    cycle(c);
    memcpy(c->CRC, c->R, sizeof(c->R));
    diffuse(c);
    for (int j = 0; j < N; j++) c->R[j] ^= c->CRC[j];
}

void s6_shannon_key(S6Shannon *c, const uint8_t *key, size_t keylen)
{
    memset(c, 0, sizeof(*c));
    c->R[0] = 1;
    c->R[1] = 1;
    for (int i = 2; i < N; i++) c->R[i] = c->R[i - 1] + c->R[i - 2];
    c->konst = INITKONST;
    loadkey(c, key, keylen);
    c->konst = c->R[0];
    memcpy(c->initR, c->R, sizeof(c->R));
    c->nbuf = 0;
}

void s6_shannon_nonce(S6Shannon *c, const uint8_t *nonce, size_t noncelen)
{
    memcpy(c->R, c->initR, sizeof(c->R));
    c->konst = INITKONST;
    loadkey(c, nonce, noncelen);
    c->konst = c->R[0];
    c->nbuf = 0;
}

void s6_shannon_nonce_u32(S6Shannon *c, uint32_t n)
{
    uint8_t b[4] = { (uint8_t)(n >> 24), (uint8_t)(n >> 16), (uint8_t)(n >> 8), (uint8_t)n };
    s6_shannon_nonce(c, b, 4);
}

// Combined MAC and encryption: the plaintext is what the MAC accumulates
void s6_shannon_encrypt(S6Shannon *c, uint8_t *buf, size_t nbytes)
{
    if (c->nbuf != 0) {
        while (c->nbuf != 0 && nbytes != 0) {
            c->mbuf ^= (uint32_t)*buf << (32 - c->nbuf);
            *buf ^= (uint8_t)((c->sbuf >> (32 - c->nbuf)) & 0xFF);
            buf++;
            c->nbuf -= 8;
            nbytes--;
        }
        if (c->nbuf != 0) return;   // not a whole word yet
        macfunc(c, c->mbuf);        // (the register was already cycled for this word)
    }
    while (nbytes >= 4) {
        cycle(c);
        uint32_t t = le32(buf);
        macfunc(c, t);
        put_le32(buf, t ^ c->sbuf);
        buf += 4;
        nbytes -= 4;
    }
    if (nbytes != 0) {
        cycle(c);
        c->mbuf = 0;
        c->nbuf = 32;
        while (c->nbuf != 0 && nbytes != 0) {
            c->mbuf ^= (uint32_t)*buf << (32 - c->nbuf);
            *buf ^= (uint8_t)((c->sbuf >> (32 - c->nbuf)) & 0xFF);
            buf++;
            c->nbuf -= 8;
            nbytes--;
        }
    }
}

// Combined MAC and decryption: the decrypted bytes are what the MAC accumulates
void s6_shannon_decrypt(S6Shannon *c, uint8_t *buf, size_t nbytes)
{
    if (c->nbuf != 0) {
        while (c->nbuf != 0 && nbytes != 0) {
            *buf ^= (uint8_t)((c->sbuf >> (32 - c->nbuf)) & 0xFF);
            c->mbuf ^= (uint32_t)*buf << (32 - c->nbuf);
            buf++;
            c->nbuf -= 8;
            nbytes--;
        }
        if (c->nbuf != 0) return;
        macfunc(c, c->mbuf);
    }
    while (nbytes >= 4) {
        cycle(c);
        uint32_t t = le32(buf) ^ c->sbuf;
        macfunc(c, t);
        put_le32(buf, t);
        buf += 4;
        nbytes -= 4;
    }
    if (nbytes != 0) {
        cycle(c);
        c->mbuf = 0;
        c->nbuf = 32;
        while (c->nbuf != 0 && nbytes != 0) {
            *buf ^= (uint8_t)((c->sbuf >> (32 - c->nbuf)) & 0xFF);
            c->mbuf ^= (uint32_t)*buf << (32 - c->nbuf);
            buf++;
            c->nbuf -= 8;
            nbytes--;
        }
    }
}

// Finishes the MAC (bytes of an unfinished word count as if the rest were zeros) and writes `nbytes` of it
void s6_shannon_finish(S6Shannon *c, uint8_t *mac, size_t nbytes)
{
    if (c->nbuf != 0) macfunc(c, c->mbuf);
    cycle(c);
    c->R[KEYP] ^= INITKONST ^ ((uint32_t)c->nbuf << 3);
    c->nbuf = 0;
    for (int i = 0; i < N; i++) c->R[i] ^= c->CRC[i];
    diffuse(c);
    while (nbytes > 0) {
        cycle(c);
        if (nbytes >= 4) {
            put_le32(mac, c->sbuf);
            mac += 4;
            nbytes -= 4;
        } else {
            for (size_t i = 0; i < nbytes; i++) mac[i] = (uint8_t)(c->sbuf >> (8 * i));
            break;
        }
    }
}
