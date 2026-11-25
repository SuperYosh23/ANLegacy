#import "S6Zeroconf.h"
#import "S6Session.h"
#import "S6Tokens.h"
#import "S6Crypto.h"
#import "S6Settings.h"
#import "S6Utils.h"
#import "S6Common.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>

NSString * const S6ZeroconfDidChangeNotification = @"S6ZeroconfDidChangeNotification";

@interface S6Zeroconf () <NSNetServiceDelegate>
@property (atomic) BOOL running;
@property (atomic) uint16_t port;
@property (atomic, copy) NSString *lastEvent;
@property (nonatomic, strong) NSNetService *service;
@property (atomic) int listenFD;
@property (nonatomic, strong) S6DHKeys *keys;
@end

typedef struct {
    const uint8_t *d;
    NSUInteger len, off;
} S6BlobCursor;

static BOOL S6BlobU8(S6BlobCursor *c, uint8_t *out)
{
    if (c->off >= c->len) return NO;
    *out = c->d[c->off++];
    return YES;
}

static BOOL S6BlobInt(S6BlobCursor *c, uint32_t *out)
{
    uint8_t lo = 0, hi = 0;
    if (!S6BlobU8(c, &lo)) return NO;
    if (!(lo & 0x80)) { *out = lo; return YES; }
    if (!S6BlobU8(c, &hi)) return NO;
    *out = (uint32_t)(lo & 0x7f) | ((uint32_t)hi << 7);
    return YES;
}

// The credentials in the blob the Spotify app sends (librespot's Credentials::with_blob): base64 of AES-192-ECB with a
// key made from this device's id and the user name, each byte XORed with the one 16 before it, then a tiny
// length-prefixed record: [?][user name][?][auth type][?][auth data]
static BOOL S6DecodeBlob(NSString *username, NSData *blobBase64, NSString *deviceId, NSInteger *authType, NSData **authData)
{
    NSData *secret = [S6Crypto sha1:[deviceId dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *derived = [S6Crypto pbkdf2SHA1Password:secret salt:[username dataUsingEncoding:NSUTF8StringEncoding] iterations:0x100 length:20];
    if (!derived) return NO;
    NSMutableData *key = [[S6Crypto sha1:derived] mutableCopy];
    uint8_t twenty[4] = { 0, 0, 0, 20 };
    [key appendBytes:twenty length:4];
    NSString *b64 = [[NSString alloc] initWithData:blobBase64 encoding:NSUTF8StringEncoding];
    NSData *encrypted = [S6Utils base64Decode:b64 ?: @""];
    if (encrypted.length < 0x11) return NO;
    // whole blocks are decrypted, a trailing partial one stays as it is (chunks_exact)
    NSUInteger whole = encrypted.length - encrypted.length % 16;
    NSMutableData *data = [[S6Crypto aes192ECBDecrypt:[encrypted subdataWithRange:NSMakeRange(0, whole)] key:key] mutableCopy];
    if (!data) return NO;
    if (whole < encrypted.length) [data appendData:[encrypted subdataWithRange:NSMakeRange(whole, encrypted.length - whole)]];
    uint8_t *d = data.mutableBytes;
    NSUInteger l = data.length;
    for (NSUInteger i = 0; i < l - 0x10; i++) d[l - i - 1] ^= d[l - i - 0x11];

    S6BlobCursor c = { d, l, 0 };
    uint8_t skip = 0;
    uint32_t len = 0, type = 0;
    if (!S6BlobU8(&c, &skip) || !S6BlobInt(&c, &len) || c.off + len > l) return NO;
    c.off += len;                                       // the user name again
    if (!S6BlobU8(&c, &skip) || !S6BlobInt(&c, &type) || !S6BlobU8(&c, &skip) || !S6BlobInt(&c, &len) || c.off + len > l) return NO;
    *authType = type;
    *authData = [NSData dataWithBytes:d + c.off length:len];
    return YES;
}

@implementation S6Zeroconf

+ (instancetype)shared
{
    static S6Zeroconf *z;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ z = [[S6Zeroconf alloc] init]; });
    return z;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _listenFD = -1;
        _keys = [S6DHKeys randomKeys];
    }
    return self;
}

- (void)setEvent:(NSString *)event
{
    self.lastEvent = event;
    S6Log(@"zeroconf: %@", event);
    S6Main(^{ [[NSNotificationCenter defaultCenter] postNotificationName:S6ZeroconfDidChangeNotification object:self]; });
}

- (void)start
{
    if (self.running) return;
    int fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0) { [self setEvent:[NSString stringWithFormat:@"no socket (%d)", errno]]; return; }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = 0;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    socklen_t length = sizeof(addr);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 || listen(fd, 8) != 0 || getsockname(fd, (struct sockaddr *)&addr, &length) != 0) {
        [self setEvent:[NSString stringWithFormat:@"cannot listen (%d)", errno]];
        close(fd);
        return;
    }
    self.port = ntohs(addr.sin_port);
    self.listenFD = fd;
    self.running = YES;
    [NSThread detachNewThreadSelector:@selector(acceptLoop:) toTarget:self withObject:@(fd)];

    self.service = [[NSNetService alloc] initWithDomain:@"" type:@"_spotify-connect._tcp." name:[S6Settings deviceName] port:self.port];
    NSDictionary *txt = @{ @"VERSION": [@"1.0" dataUsingEncoding:NSUTF8StringEncoding],
                           @"CPath": [@"/" dataUsingEncoding:NSUTF8StringEncoding] };
    [self.service setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:txt]];
    self.service.delegate = self;
    [self.service publish];
    [self setEvent:[NSString stringWithFormat:@"announced as \"%@\" on port %u", [S6Settings deviceName], self.port]];
}

- (void)stop
{
    if (!self.running) return;
    self.running = NO;
    [self.service stop];
    self.service = nil;
    int fd = self.listenFD;
    self.listenFD = -1;
    if (fd >= 0) close(fd);
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
{
    [self setEvent:[NSString stringWithFormat:@"Bonjour did not publish: %@", errorDict]];
}

#pragma mark - HTTP

- (void)acceptLoop:(NSNumber *)fdNumber
{
    @autoreleasepool { [[NSThread currentThread] setName:@"S6Zeroconf"]; }
    int fd = fdNumber.intValue;
    while (self.listenFD == fd) {
        @autoreleasepool {
            int c = accept(fd, NULL, NULL);
            if (c < 0) {
                if (errno == EINTR) continue;
                break;
            }
            int on = 1;
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
            struct timeval tv = { 10, 0 };
            setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
            [self serve:c];
            close(c);
        }
    }
}

static NSDictionary *S6ParseForm(NSString *s)
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *pair in [s componentsSeparatedByString:@"&"]) {
        NSRange eq = [pair rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *k = [[[pair substringToIndex:eq.location] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *v = [[[pair substringFromIndex:eq.location + 1] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (k) [d setObject:(v ?: @"") forKey:k];
    }
    return d;
}

- (void)serve:(int)fd
{
    NSMutableData *buf = [NSMutableData data];
    NSData *blank = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange end = NSMakeRange(NSNotFound, 0);
    char chunk[4096];
    while (buf.length < 65536) {
        ssize_t n = recv(fd, chunk, sizeof(chunk), 0);
        if (n <= 0) return;
        [buf appendBytes:chunk length:(NSUInteger)n];
        end = [buf rangeOfData:blank options:0 range:NSMakeRange(0, buf.length)];
        if (end.location != NSNotFound) break;
    }
    if (end.location == NSNotFound) return;
    NSString *head = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(0, end.location)] encoding:NSISOLatin1StringEncoding] ?: @"";
    NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
    NSArray *requestLine = [[lines count] ? [lines objectAtIndex:0] : @"" componentsSeparatedByString:@" "];
    if (requestLine.count < 2) return;
    NSString *method = [[requestLine objectAtIndex:0] uppercaseString];
    NSString *target = [requestLine objectAtIndex:1];
    NSInteger contentLength = 0;
    for (NSString *line in lines) {
        if ([[line lowercaseString] hasPrefix:@"content-length:"]) contentLength = [[line substringFromIndex:15] integerValue];
    }
    NSUInteger bodyStart = end.location + 4;
    while ((NSInteger)(buf.length - bodyStart) < contentLength && buf.length < 262144) {
        ssize_t n = recv(fd, chunk, sizeof(chunk), 0);
        if (n <= 0) break;
        [buf appendBytes:chunk length:(NSUInteger)n];
    }
    NSString *body = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(bodyStart, buf.length - bodyStart)] encoding:NSUTF8StringEncoding] ?: @"";
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSRange q = [target rangeOfString:@"?"];
    if (q.location != NSNotFound) [params addEntriesFromDictionary:S6ParseForm([target substringFromIndex:q.location + 1])];
    [params addEntriesFromDictionary:S6ParseForm(body)];
    NSString *action = [params objectForKey:@"action"];

    NSDictionary *reply;
    if ([method isEqualToString:@"GET"] && [action isEqualToString:@"getInfo"]) {
        reply = [self info];
        [self setEvent:@"the Spotify app asked who this is"];
    } else if ([method isEqualToString:@"POST"] && [action isEqualToString:@"addUser"]) {
        reply = [self addUser:params];
    } else {
        NSString *notFound = @"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        send(fd, notFound.UTF8String, strlen(notFound.UTF8String), 0);
        return;
    }
    NSData *json = [S6Utils JSONDataFromObject:reply] ?: [NSData data];
    NSString *headOut = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", (unsigned long)json.length];
    NSMutableData *out = [[headOut dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
    [out appendData:json];
    const uint8_t *p = out.bytes;
    NSUInteger left = out.length;
    while (left > 0) {
        ssize_t n = send(fd, p, left, 0);
        if (n <= 0) break;
        p += n;
        left -= (NSUInteger)n;
    }
}

- (NSDictionary *)info
{
    return @{
        @"status": @101,
        @"statusString": @"OK",
        @"spotifyError": @0,
        @"version": @"2.9.0",
        @"deviceID": [S6Settings deviceId],
        @"deviceType": S6IsPad() ? @"Tablet" : @"Smartphone",
        @"remoteName": [S6Settings deviceName],
        @"publicKey": [S6Utils base64Encode:self.keys.publicKey] ?: @"",
        @"brandDisplayName": @"Sixify",
        @"modelDisplayName": S6IsPad() ? @"iPad" : @"iPhone",
        @"libraryVersion": @"0.8.0",
        @"resolverVersion": @"1",
        @"groupStatus": @"NONE",
        @"tokenType": @"default",
        @"clientID": S6ClientId,
        @"productID": @0,
        @"scope": @"streaming",
        @"availability": @"",
        @"supported_drm_media_formats": [NSArray array],
        @"supported_capabilities": @1,
        @"accountReq": @"PREMIUM",
        @"activeUser": [S6Session shared].username ?: @"",
        @"aliases": [NSArray array],
    };
}

- (NSDictionary *)addUser:(NSDictionary *)params
{
    NSString *username = [params objectForKey:@"userName"];
    NSData *blob = [S6Utils base64Decode:[params objectForKey:@"blob"] ?: @""];
    NSData *clientKey = [S6Utils base64Decode:[params objectForKey:@"clientKey"] ?: @""];
    if (!username.length || blob.length < 36 || !clientKey.length) {
        [self setEvent:@"an incomplete login arrived"];
        return @{ @"status": @102, @"spotifyError": @1, @"statusString": @"ERROR-MISSING-PARAMS" };
    }
    NSData *shared = [self.keys sharedSecretWith:clientKey];
    NSData *baseKey = [[S6Crypto sha1:shared] subdataWithRange:NSMakeRange(0, 16)];
    NSData *checksumKey = [S6Crypto hmacSHA1Key:baseKey parts:@[ [@"checksum" dataUsingEncoding:NSASCIIStringEncoding] ]];
    NSData *encryptionKey = [[S6Crypto hmacSHA1Key:baseKey parts:@[ [@"encryption" dataUsingEncoding:NSASCIIStringEncoding] ]] subdataWithRange:NSMakeRange(0, 16)];
    NSData *iv = [blob subdataWithRange:NSMakeRange(0, 16)];
    NSData *encrypted = [blob subdataWithRange:NSMakeRange(16, blob.length - 36)];
    NSData *checksum = [blob subdataWithRange:NSMakeRange(blob.length - 20, 20)];
    if (![[S6Crypto hmacSHA1Key:checksumKey parts:@[ encrypted ]] isEqualToData:checksum]) {
        [self setEvent:@"the login did not decrypt (MAC mismatch)"];
        return @{ @"status": @102, @"spotifyError": @1, @"statusString": @"ERROR-MAC" };
    }
    NSData *decrypted = [S6Crypto aes128CTR:encrypted key:encryptionKey iv:iv];
    NSInteger authType = 0;
    NSData *authData = nil;
    if (!S6DecodeBlob(username, decrypted, [S6Settings deviceId], &authType, &authData) || !authData.length) {
        [self setEvent:@"the login blob could not be read"];
        return @{ @"status": @102, @"spotifyError": @1, @"statusString": @"ERROR-BLOB" };
    }
    S6Session *session = [S6Session shared];
    if (session.state == S6SessionStateReady && session.username.length && [session.username caseInsensitiveCompare:username] == NSOrderedSame) {
        // (the phone asks again whenever its device list opens: the same account stays as it is)
        [self setEvent:[NSString stringWithFormat:@"login for %@ arrived, already logged in", username]];
        return @{ @"status": @101, @"spotifyError": @0, @"statusString": @"OK" };
    }
    [self setEvent:[NSString stringWithFormat:@"login for %@ arrived, logging in", username]];
    [session loginWithUsername:username authType:authType authData:authData];
    return @{ @"status": @101, @"spotifyError": @0, @"statusString": @"OK" };
}

@end
