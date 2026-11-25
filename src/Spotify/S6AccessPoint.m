#import "S6AccessPoint.h"
#import "S6TLSSocket.h"
#import "S6Proto.h"
#import "S6Crypto.h"
#import "S6Shannon.h"
#import "S6Common.h"

// Spotify's access point key: its signature over the server's Diffie-Hellman key proves the other end is Spotify
static const uint8_t S6ServerKey[256] = {
    0xac, 0xe0, 0x46, 0x0b, 0xff, 0xc2, 0x30, 0xaf, 0xf4, 0x6b, 0xfe, 0xc3, 0xbf, 0xbf, 0x86, 0x3d,
    0xa1, 0x91, 0xc6, 0xcc, 0x33, 0x6c, 0x93, 0xa1, 0x4f, 0xb3, 0xb0, 0x16, 0x12, 0xac, 0xac, 0x6a,
    0xf1, 0x80, 0xe7, 0xf6, 0x14, 0xd9, 0x42, 0x9d, 0xbe, 0x2e, 0x34, 0x66, 0x43, 0xe3, 0x62, 0xd2,
    0x32, 0x7a, 0x1a, 0x0d, 0x92, 0x3b, 0xae, 0xdd, 0x14, 0x02, 0xb1, 0x81, 0x55, 0x05, 0x61, 0x04,
    0xd5, 0x2c, 0x96, 0xa4, 0x4c, 0x1e, 0xcc, 0x02, 0x4a, 0xd4, 0xb2, 0x0c, 0x00, 0x1f, 0x17, 0xed,
    0xc2, 0x2f, 0xc4, 0x35, 0x21, 0xc8, 0xf0, 0xcb, 0xae, 0xd2, 0xad, 0xd7, 0x2b, 0x0f, 0x9d, 0xb3,
    0xc5, 0x32, 0x1a, 0x2a, 0xfe, 0x59, 0xf3, 0x5a, 0x0d, 0xac, 0x68, 0xf1, 0xfa, 0x62, 0x1e, 0xfb,
    0x2c, 0x8d, 0x0c, 0xb7, 0x39, 0x2d, 0x92, 0x47, 0xe3, 0xd7, 0x35, 0x1a, 0x6d, 0xbd, 0x24, 0xc2,
    0xae, 0x25, 0x5b, 0x88, 0xff, 0xab, 0x73, 0x29, 0x8a, 0x0b, 0xcc, 0xcd, 0x0c, 0x58, 0x67, 0x31,
    0x89, 0xe8, 0xbd, 0x34, 0x80, 0x78, 0x4a, 0x5f, 0xc9, 0x6b, 0x89, 0x9d, 0x95, 0x6b, 0xfc, 0x86,
    0xd7, 0x4f, 0x33, 0xa6, 0x78, 0x17, 0x96, 0xc9, 0xc3, 0x2d, 0x0d, 0x32, 0xa5, 0xab, 0xcd, 0x05,
    0x27, 0xe2, 0xf7, 0x10, 0xa3, 0x96, 0x13, 0xc4, 0x2f, 0x99, 0xc0, 0x27, 0xbf, 0xed, 0x04, 0x9c,
    0x3c, 0x27, 0x58, 0x04, 0xb6, 0xb2, 0x19, 0xf9, 0xc1, 0x2f, 0x02, 0xe9, 0x48, 0x63, 0xec, 0xa1,
    0xb6, 0x42, 0xa0, 0x9d, 0x48, 0x25, 0xf8, 0xb3, 0x9d, 0xd0, 0xe8, 0x6a, 0xf9, 0x48, 0x4d, 0xa1,
    0xc2, 0xba, 0x86, 0x30, 0x42, 0xea, 0x9d, 0xb3, 0x08, 0x6c, 0x19, 0x0e, 0x48, 0xb3, 0x9d, 0x66,
    0xeb, 0x00, 0x06, 0xa2, 0x5a, 0xee, 0xa1, 0x1b, 0x13, 0x87, 0x3c, 0xd7, 0x19, 0xe6, 0x55, 0xbd,
};

static const uint64_t S6SpotifyVersion = 124200290;     // the desktop client version librespot reports
static const uint32_t S6PlatformLinuxArm = 0x11;

static NSString *S6APErrorText(uint64_t code)
{
    switch (code) {
        case 0x02: return L(@"Spotify asked to try another server.");
        case 0x09: return L(@"Spotify does not allow logging in from this country.");
        case 0x0b: return L(@"Spotify Premium is required.");
        case 0x0c:
        case 0x0d: return L(@"Spotify did not accept the login.");
        case 0x0f: return L(@"Spotify wants an extra confirmation that Sixify cannot give.");
        default: return [NSString stringWithFormat:L(@"Spotify refused the connection (error %llu)."), code];   // 5 bad connection id, 0x10 app key, 0x11 banned
    }
}

@interface S6AccessPoint ()
@property (atomic) BOOL connected;
@property (nonatomic, copy) NSString *host;
@end

@implementation S6AccessPoint {
    S6TLSSocket *_socket;
    S6Shannon _send, _recv;
    uint32_t _sendNonce, _recvNonce;
    NSLock *_sendLock;
}

- (instancetype)init
{
    if ((self = [super init])) _sendLock = [[NSLock alloc] init];
    return self;
}

- (BOOL)readExactly:(uint8_t *)buf length:(NSUInteger)length error:(NSError **)error
{
    NSUInteger got = 0;
    while (got < length) {
        NSError *e = nil;
        NSInteger n = [_socket readIntoBuffer:buf + got maxLength:length - got error:&e];
        if (n <= 0) {
            if (error) *error = e ?: S6MakeError(S6ErrorConnectionLost, L(@"The connection to Spotify was closed."));
            return NO;
        }
        got += (NSUInteger)n;
    }
    return YES;
}

static NSData *S6U32(uint32_t v)
{
    uint8_t b[4] = { (uint8_t)(v >> 24), (uint8_t)(v >> 16), (uint8_t)(v >> 8), (uint8_t)v };
    return [NSData dataWithBytes:b length:4];
}

- (BOOL)connectToHost:(NSString *)host port:(int)port error:(NSError **)error
{
    self.host = host;
    _socket = [[S6TLSSocket alloc] init];
    _socket.plain = YES;
    if (![_socket connectToHost:host port:port verify:NO connectTimeoutMs:8000 readTimeoutMs:10000 error:error]) return NO;

    // ClientHello: our Diffie-Hellman key and who we are (librespot's identity on Linux ARM)
    S6DHKeys *dh = [S6DHKeys randomKeys];
    S6ProtoWriter *build = [S6ProtoWriter writer];
    [build varint:0 field:10];                      // product: PRODUCT_CLIENT
    [build varint:0 field:20];                      // product_flags: PRODUCT_FLAG_NONE
    [build varint:S6PlatformLinuxArm field:30];     // platform
    [build varint:S6SpotifyVersion field:40];       // version
    S6ProtoWriter *dhHello = [S6ProtoWriter writer];
    [dhHello bytes:dh.publicKey field:10];          // gc
    [dhHello varint:1 field:20];                    // server_keys_known
    S6ProtoWriter *cryptoHello = [S6ProtoWriter writer];
    [cryptoHello message:dhHello field:10];
    S6ProtoWriter *hello = [S6ProtoWriter writer];
    [hello message:build field:10];
    [hello varint:0 field:30];                      // cryptosuites_supported: SHANNON
    [hello message:cryptoHello field:50];
    [hello bytes:[S6Crypto randomBytes:16] field:60];    // client_nonce
    uint8_t padding = 0x1e;
    [hello bytes:[NSData dataWithBytes:&padding length:1] field:70];
    NSData *helloBytes = hello.data;

    NSMutableData *accumulator = [NSMutableData data];
    uint8_t magic[2] = { 0x00, 0x04 };
    [accumulator appendBytes:magic length:2];
    [accumulator appendData:S6U32((uint32_t)(2 + 4 + helloBytes.length))];
    [accumulator appendData:helloBytes];
    if (![_socket writeData:accumulator error:error]) return NO;

    // APResponseMessage
    uint8_t sizeBytes[4];
    if (![self readExactly:sizeBytes length:4 error:error]) return NO;
    uint32_t size = ((uint32_t)sizeBytes[0] << 24) | ((uint32_t)sizeBytes[1] << 16) | ((uint32_t)sizeBytes[2] << 8) | sizeBytes[3];
    if (size < 4 || size > 65536) { if (error) *error = S6MakeError(S6ErrorBadResponse, L(@"Spotify sent something unexpected.")); return NO; }
    NSMutableData *response = [NSMutableData dataWithLength:size - 4];
    if (![self readExactly:response.mutableBytes length:size - 4 error:error]) return NO;
    [accumulator appendBytes:sizeBytes length:4];
    [accumulator appendData:response];

    NSData *challenge = S6ProtoBytes(response, 10);
    if (!challenge) {
        NSData *failed = S6ProtoBytes(response, 30);
        uint64_t code = failed ? S6ProtoVarint(failed, 10, 0) : 0;
        if (error) *error = S6MakeError(S6ErrorAuth, failed ? S6APErrorText(code) : L(@"Spotify sent something unexpected."));
        return NO;
    }
    NSData *dhChallenge = S6ProtoBytes(S6ProtoBytes(challenge, 10), 10);
    NSData *gs = S6ProtoBytes(dhChallenge, 10);
    NSData *signature = S6ProtoBytes(dhChallenge, 30);
    if (!gs.length || ![S6Crypto verifyRSASHA1Signature:signature ofData:gs modulus:[NSData dataWithBytes:S6ServerKey length:sizeof(S6ServerKey)]]) {
        if (error) *error = S6MakeError(S6ErrorTLS, L(@"The server could not prove that it is Spotify."));
        return NO;
    }

    // the keys: HMAC-SHA1 over everything exchanged so far, keyed with the shared secret
    NSData *shared = [dh sharedSecretWith:gs];
    NSMutableData *keyData = [NSMutableData dataWithCapacity:100];
    for (uint8_t i = 1; i <= 5; i++) {
        NSData *part = [S6Crypto hmacSHA1Key:shared parts:@[ accumulator, [NSData dataWithBytes:&i length:1] ]];
        if (!part) { if (error) *error = S6MakeError(S6ErrorTLS, L(@"The connection to Spotify could not be secured.")); return NO; }
        [keyData appendData:part];
    }
    NSData *answer = [S6Crypto hmacSHA1Key:[keyData subdataWithRange:NSMakeRange(0, 0x14)] parts:@[ accumulator ]];
    NSData *sendKey = [keyData subdataWithRange:NSMakeRange(0x14, 0x20)];
    NSData *recvKey = [keyData subdataWithRange:NSMakeRange(0x34, 0x20)];

    // ClientResponsePlaintext: the answer to the challenge (no proof of work, no extra crypto)
    S6ProtoWriter *dhResponse = [S6ProtoWriter writer];
    [dhResponse bytes:answer field:10];
    S6ProtoWriter *loginResponse = [S6ProtoWriter writer];
    [loginResponse message:dhResponse field:10];
    S6ProtoWriter *plain = [S6ProtoWriter writer];
    [plain message:loginResponse field:10];
    [plain message:[S6ProtoWriter writer] field:20];
    [plain message:[S6ProtoWriter writer] field:30];
    NSData *plainBytes = plain.data;
    NSMutableData *out = [NSMutableData dataWithData:S6U32((uint32_t)(4 + plainBytes.length))];
    [out appendData:plainBytes];
    if (![_socket writeData:out error:error]) return NO;

    s6_shannon_key(&_send, sendKey.bytes, sendKey.length);
    s6_shannon_key(&_recv, recvKey.bytes, recvKey.length);
    _sendNonce = 0;
    _recvNonce = 0;
    self.connected = YES;
    return YES;
}

- (BOOL)sendPacket:(uint8_t)command payload:(NSData *)payload error:(NSError **)error
{
    if (!self.connected) { if (error) *error = S6MakeError(S6ErrorConnectionLost, L(@"Not connected to Spotify.")); return NO; }
    NSUInteger len = payload.length;
    if (len > 0xFFFF) { if (error) *error = S6MakeError(S6ErrorBadResponse, L(@"Spotify sent something unexpected.")); return NO; }
    NSMutableData *buf = [NSMutableData dataWithLength:3 + len + 4];
    uint8_t *p = buf.mutableBytes;
    p[0] = command;
    p[1] = (uint8_t)(len >> 8);
    p[2] = (uint8_t)len;
    if (len) memcpy(p + 3, payload.bytes, len);
    [_sendLock lock];
    s6_shannon_nonce_u32(&_send, _sendNonce++);
    s6_shannon_encrypt(&_send, p, 3 + len);
    s6_shannon_finish(&_send, p + 3 + len, 4);
    BOOL ok = [_socket writeData:buf error:error];
    [_sendLock unlock];
    if (!ok) self.connected = NO;
    return ok;
}

- (BOOL)receivePacket:(uint8_t *)command payload:(NSData **)payload error:(NSError **)error
{
    uint8_t header[3];
    if (!self.connected || ![self readExactly:header length:3 error:error]) { self.connected = NO; return NO; }
    s6_shannon_nonce_u32(&_recv, _recvNonce++);
    s6_shannon_decrypt(&_recv, header, 3);
    NSUInteger size = ((NSUInteger)header[1] << 8) | header[2];
    NSMutableData *data = [NSMutableData dataWithLength:size + 4];
    if (![self readExactly:data.mutableBytes length:size + 4 error:error]) { self.connected = NO; return NO; }
    uint8_t *p = data.mutableBytes;
    s6_shannon_decrypt(&_recv, p, size);
    uint8_t mac[4];
    s6_shannon_finish(&_recv, mac, 4);
    if (memcmp(mac, p + size, 4) != 0) {
        if (error) *error = S6MakeError(S6ErrorTLS, L(@"The connection to Spotify could not be secured."));
        self.connected = NO;
        return NO;
    }
    *command = header[0];
    *payload = [data subdataWithRange:NSMakeRange(0, size)];
    return YES;
}

- (void)setReadTimeout:(NSTimeInterval)seconds { [_socket setReadTimeoutMs:(uint32_t)(seconds * 1000)]; }

- (void)close
{
    self.connected = NO;
    [_socket cancel];
    [_socket close];
}

@end
