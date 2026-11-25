#import "S6Crypto.h"
#import <Security/Security.h>

#include "mbedtls/sha1.h"
#include "mbedtls/md.h"
#include "mbedtls/pkcs5.h"
#include "mbedtls/aes.h"
#include "mbedtls/bignum.h"
#include "mbedtls/rsa.h"

static const uint8_t S6DHPrime[96] = {
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xc9, 0x0f, 0xda, 0xa2, 0x21, 0x68, 0xc2, 0x34,
    0xc4, 0xc6, 0x62, 0x8b, 0x80, 0xdc, 0x1c, 0xd1, 0x29, 0x02, 0x4e, 0x08, 0x8a, 0x67, 0xcc, 0x74,
    0x02, 0x0b, 0xbe, 0xa6, 0x3b, 0x13, 0x9b, 0x22, 0x51, 0x4a, 0x08, 0x79, 0x8e, 0x34, 0x04, 0xdd,
    0xef, 0x95, 0x19, 0xb3, 0xcd, 0x3a, 0x43, 0x1b, 0x30, 0x2b, 0x0a, 0x6d, 0xf2, 0x5f, 0x14, 0x37,
    0x4f, 0xe1, 0x35, 0x6d, 0x6d, 0x51, 0xc2, 0x45, 0xe4, 0x85, 0xb5, 0x76, 0x62, 0x5e, 0x7e, 0xc6,
    0xf4, 0x4c, 0x42, 0xe9, 0xa6, 0x3a, 0x36, 0x20, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
};

static const uint8_t S6AudioIV[16] = {
    0x72, 0xe0, 0x67, 0xfb, 0xdd, 0xcb, 0xcf, 0x77, 0xeb, 0xe8, 0xbc, 0x64, 0x3f, 0x63, 0x0d, 0x93,
};

// minimal big-endian bytes of an mpi (as BigUint::to_bytes_be gives them)
static NSData *S6MPIBytes(const mbedtls_mpi *x)
{
    size_t n = mbedtls_mpi_size(x);
    if (n == 0) { uint8_t z = 0; return [NSData dataWithBytes:&z length:1]; }
    NSMutableData *d = [NSMutableData dataWithLength:n];
    if (mbedtls_mpi_write_binary(x, d.mutableBytes, n) != 0) return nil;
    return d;
}

@implementation S6Crypto

+ (NSData *)randomBytes:(NSUInteger)count
{
    NSMutableData *d = [NSMutableData dataWithLength:count];
    if (SecRandomCopyBytes(kSecRandomDefault, count, d.mutableBytes) != 0) {
        uint8_t *p = d.mutableBytes;
        for (NSUInteger i = 0; i < count; i++) p[i] = (uint8_t)arc4random();
    }
    return d;
}

+ (NSData *)sha1:(NSData *)data
{
    uint8_t out[20];
    mbedtls_sha1(data.bytes, data.length, out);
    return [NSData dataWithBytes:out length:20];
}

+ (NSData *)hmacSHA1Key:(NSData *)key parts:(NSArray *)parts
{
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA1);
    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    uint8_t out[20];
    BOOL ok = mbedtls_md_setup(&ctx, info, 1) == 0 && mbedtls_md_hmac_starts(&ctx, key.bytes, key.length) == 0;
    for (NSData *p in parts) if (ok) ok = mbedtls_md_hmac_update(&ctx, p.bytes, p.length) == 0;
    if (ok) ok = mbedtls_md_hmac_finish(&ctx, out) == 0;
    mbedtls_md_free(&ctx);
    return ok ? [NSData dataWithBytes:out length:20] : nil;
}

+ (NSData *)pbkdf2SHA1Password:(NSData *)password salt:(NSData *)salt iterations:(unsigned)iterations length:(NSUInteger)length
{
    NSMutableData *out = [NSMutableData dataWithLength:length];
    int rc = mbedtls_pkcs5_pbkdf2_hmac_ext(MBEDTLS_MD_SHA1, password.bytes, password.length, salt.bytes, salt.length,
                                           iterations, (uint32_t)length, out.mutableBytes);
    return rc == 0 ? out : nil;
}

+ (NSData *)aes192ECBDecrypt:(NSData *)data key:(NSData *)key
{
    if (key.length != 24 || data.length % 16) return nil;
    mbedtls_aes_context ctx;
    mbedtls_aes_init(&ctx);
    NSMutableData *out = [NSMutableData dataWithLength:data.length];
    BOOL ok = mbedtls_aes_setkey_dec(&ctx, key.bytes, 192) == 0;
    const uint8_t *in = data.bytes;
    uint8_t *o = out.mutableBytes;
    for (NSUInteger i = 0; ok && i < data.length; i += 16) ok = mbedtls_aes_crypt_ecb(&ctx, MBEDTLS_AES_DECRYPT, in + i, o + i) == 0;
    mbedtls_aes_free(&ctx);
    return ok ? out : nil;
}

+ (NSData *)aes128CTR:(NSData *)data key:(NSData *)key iv:(NSData *)iv
{
    if (key.length != 16 || iv.length != 16) return nil;
    mbedtls_aes_context ctx;
    mbedtls_aes_init(&ctx);
    NSMutableData *out = [NSMutableData dataWithLength:data.length];
    uint8_t counter[16], block[16];
    memcpy(counter, iv.bytes, 16);
    size_t off = 0;
    BOOL ok = mbedtls_aes_setkey_enc(&ctx, key.bytes, 128) == 0 &&
              mbedtls_aes_crypt_ctr(&ctx, data.length, &off, counter, block, data.bytes, out.mutableBytes) == 0;
    mbedtls_aes_free(&ctx);
    return ok ? out : nil;
}

+ (BOOL)verifyRSASHA1Signature:(NSData *)signature ofData:(NSData *)data modulus:(NSData *)modulus
{
    static const uint8_t e[3] = { 0x01, 0x00, 0x01 };
    uint8_t hash[20];
    mbedtls_sha1(data.bytes, data.length, hash);
    mbedtls_rsa_context rsa;
    mbedtls_rsa_init(&rsa);
    BOOL ok = mbedtls_rsa_import_raw(&rsa, modulus.bytes, modulus.length, NULL, 0, NULL, 0, NULL, 0, e, 3) == 0 &&
              mbedtls_rsa_complete(&rsa) == 0 &&
              signature.length == mbedtls_rsa_get_len(&rsa) &&
              mbedtls_rsa_pkcs1_verify(&rsa, MBEDTLS_MD_SHA1, 20, hash, signature.bytes) == 0;
    mbedtls_rsa_free(&rsa);
    return ok;
}

+ (NSString *)hex:(NSData *)data
{
    const uint8_t *p = data.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [s appendFormat:@"%02x", p[i]];
    return s;
}

+ (NSString *)hexUpper:(NSData *)data { return [[self hex:data] uppercaseString]; }

+ (NSData *)dataFromHex:(NSString *)hex
{
    if (hex.length % 2) return nil;
    NSMutableData *d = [NSMutableData dataWithCapacity:hex.length / 2];
    for (NSUInteger i = 0; i < hex.length; i += 2) {
        unsigned v = 0;
        NSScanner *sc = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]];
        if (![sc scanHexInt:&v]) return nil;
        uint8_t b = (uint8_t)v;
        [d appendBytes:&b length:1];
    }
    return d;
}

@end

@implementation S6DHKeys {
    mbedtls_mpi _private;
    NSData *_public;
}

+ (instancetype)randomKeys { return [[self alloc] init]; }

- (instancetype)init
{
    if ((self = [super init])) {
        mbedtls_mpi_init(&_private);
        NSData *r = [S6Crypto randomBytes:95];
        mbedtls_mpi g, p, pub;
        mbedtls_mpi_init(&g); mbedtls_mpi_init(&p); mbedtls_mpi_init(&pub);
        mbedtls_mpi_read_binary(&_private, r.bytes, r.length);
        mbedtls_mpi_lset(&g, 2);
        mbedtls_mpi_read_binary(&p, S6DHPrime, sizeof(S6DHPrime));
        if (mbedtls_mpi_exp_mod(&pub, &g, &_private, &p, NULL) == 0) _public = S6MPIBytes(&pub);
        mbedtls_mpi_free(&g); mbedtls_mpi_free(&p); mbedtls_mpi_free(&pub);
    }
    return self;
}

- (void)dealloc { mbedtls_mpi_free(&_private); }

- (NSData *)publicKey { return _public; }

- (NSData *)sharedSecretWith:(NSData *)remotePublicKey
{
    mbedtls_mpi remote, p, shared;
    mbedtls_mpi_init(&remote); mbedtls_mpi_init(&p); mbedtls_mpi_init(&shared);
    mbedtls_mpi_read_binary(&remote, remotePublicKey.bytes, remotePublicKey.length);
    mbedtls_mpi_read_binary(&p, S6DHPrime, sizeof(S6DHPrime));
    NSData *out = nil;
    if (mbedtls_mpi_exp_mod(&shared, &remote, &_private, &p, NULL) == 0) out = S6MPIBytes(&shared);
    mbedtls_mpi_free(&remote); mbedtls_mpi_free(&p); mbedtls_mpi_free(&shared);
    return out;
}

@end

@implementation S6AudioDecrypt {
    mbedtls_aes_context _aes;
    uint8_t _counter[16];
    uint8_t _block[16];
    size_t _off;
}

- (instancetype)initWithKey:(NSData *)key offset:(uint64_t)offset
{
    if ((self = [super init])) {
        mbedtls_aes_init(&_aes);
        if (key.length == 16) mbedtls_aes_setkey_enc(&_aes, key.bytes, 128);
        memcpy(_counter, S6AudioIV, 16);
        // counter = IV + offset / 16 (128-bit big-endian)
        uint64_t add = offset / 16;
        for (int i = 15; i >= 0 && add; i--) {
            uint64_t sum = (uint64_t)_counter[i] + (add & 0xFF);
            _counter[i] = (uint8_t)sum;
            add = (add >> 8) + (sum >> 8);
        }
        _off = 0;
        if (offset % 16) {
            // the keystream block of this counter, partly used already
            mbedtls_aes_crypt_ecb(&_aes, MBEDTLS_AES_ENCRYPT, _counter, _block);
            for (int i = 15; i >= 0; i--) if (++_counter[i]) break;
            _off = (size_t)(offset % 16);
        }
    }
    return self;
}

- (void)dealloc { mbedtls_aes_free(&_aes); }

- (void)decrypt:(uint8_t *)bytes length:(NSUInteger)length
{
    if (length) mbedtls_aes_crypt_ctr(&_aes, length, &_off, _counter, _block, bytes, bytes);
}

@end

#pragma mark - Base62

static const char *S6Base62Alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

NSData *S6GidFromBase62(NSString *base62)
{
    if (base62.length != 22) return nil;
    uint8_t n[16] = { 0 };
    for (NSUInteger i = 0; i < 22; i++) {
        unichar c = [base62 characterAtIndex:i];
        const char *pos = c < 128 ? strchr(S6Base62Alphabet, (int)c) : NULL;
        if (!pos || !c) return nil;
        unsigned carry = (unsigned)(pos - S6Base62Alphabet);
        for (int j = 15; j >= 0; j--) {
            unsigned v = (unsigned)n[j] * 62 + carry;
            n[j] = (uint8_t)v;
            carry = v >> 8;
        }
    }
    return [NSData dataWithBytes:n length:16];
}

NSString *S6Base62FromGid(NSData *gid)
{
    if (gid.length != 16) return nil;
    uint8_t n[16];
    memcpy(n, gid.bytes, 16);
    char out[23];
    for (int k = 21; k >= 0; k--) {
        unsigned rem = 0;
        for (int j = 0; j < 16; j++) {
            unsigned v = (rem << 8) | n[j];
            n[j] = (uint8_t)(v / 62);
            rem = v % 62;
        }
        out[k] = S6Base62Alphabet[rem];
    }
    out[22] = 0;
    return [NSString stringWithUTF8String:out];
}
