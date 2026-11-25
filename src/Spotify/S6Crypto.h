#import <Foundation/Foundation.h>

// Cryptography for Spotify's protocols, on the bundled mbedTLS
@interface S6Crypto : NSObject

+ (NSData *)randomBytes:(NSUInteger)count;
+ (NSData *)sha1:(NSData *)data;
+ (NSData *)hmacSHA1Key:(NSData *)key parts:(NSArray *)parts;   // NSData parts, hashed one after another
+ (NSData *)pbkdf2SHA1Password:(NSData *)password salt:(NSData *)salt iterations:(unsigned)iterations length:(NSUInteger)length;
+ (NSData *)aes192ECBDecrypt:(NSData *)data key:(NSData *)key;    // whole 16-byte blocks, no padding
+ (NSData *)aes128CTR:(NSData *)data key:(NSData *)key iv:(NSData *)iv;
// PKCS#1 v1.5 with SHA-1, e = 65537
+ (BOOL)verifyRSASHA1Signature:(NSData *)signature ofData:(NSData *)data modulus:(NSData *)modulus;

+ (NSString *)hex:(NSData *)data;                     // lowercase
+ (NSString *)hexUpper:(NSData *)data;
+ (NSData *)dataFromHex:(NSString *)hex;

@end

// Diffie-Hellman in Spotify's 768-bit group (RFC 2409 group 1, generator 2), keys as minimal big-endian bytes
@interface S6DHKeys : NSObject
+ (instancetype)randomKeys;
@property (nonatomic, readonly) NSData *publicKey;
- (NSData *)sharedSecretWith:(NSData *)remotePublicKey;
@end

// AES-128-CTR as Spotify encrypts audio files: a fixed IV, the counter running from the start of the file; can start
// at any byte offset and then decrypts sequentially
@interface S6AudioDecrypt : NSObject
- (instancetype)initWithKey:(NSData *)key offset:(uint64_t)offset;
- (void)decrypt:(uint8_t *)bytes length:(NSUInteger)length;
@end

// Spotify's 22-character base62 ids and their 16-byte form ("gid")
NSData *S6GidFromBase62(NSString *base62);
NSString *S6Base62FromGid(NSData *gid);
