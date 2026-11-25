#import "S6WebSocket.h"
#import "S6Utils.h"
#import "S6Common.h"

#include <string.h>
#include <stdlib.h>

static const NSUInteger S6WebSocketMaxFrame = 8 * 1024 * 1024;     // a cluster state with a long queue is a few hundred KB
static const NSUInteger S6WebSocketMaxHeader = 16 * 1024;

enum {
    S6OpContinuation = 0x0,
    S6OpText         = 0x1,
    S6OpBinary       = 0x2,
    S6OpClose        = 0x8,
    S6OpPing         = 0x9,
    S6OpPong         = 0xA,
};

@interface S6WebSocket ()
@property (nonatomic, strong) S6TLSSocket *socket;
@end

@implementation S6WebSocket {
    NSMutableData *_incoming;        // bytes received, not yet taken apart into frames
    NSMutableData *_message;         // the fragments of a message under way
    BOOL _messageIsText;
    NSLock *_writeLock;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _incoming = [NSMutableData data];
        _writeLock = [[NSLock alloc] init];
    }
    return self;
}

#pragma mark - Connecting

- (BOOL)connectToURL:(NSURL *)url origin:(NSString *)origin userAgent:(NSString *)userAgent verify:(BOOL)verify error:(NSError **)error
{
    NSString *scheme = [url.scheme lowercaseString];
    BOOL secure = [scheme isEqualToString:@"wss"] || [scheme isEqualToString:@"https"];
    int port = url.port ? url.port.intValue : (secure ? 443 : 80);
    S6TLSSocket *socket = [[S6TLSSocket alloc] init];
    socket.plain = !secure;
    self.socket = socket;
    if (![socket connectToHost:url.host port:port verify:verify connectTimeoutMs:15000 readTimeoutMs:15000 error:error]) return NO;

    uint8_t nonce[16];
    for (int i = 0; i < 16; i++) nonce[i] = (uint8_t)(arc4random() % 256);
    NSString *key = [S6Utils base64Encode:[NSData dataWithBytes:nonce length:sizeof(nonce)]];
    NSString *path = url.path.length ? url.path : @"/";
    NSString *query = url.query.length ? [@"?" stringByAppendingString:url.query] : @"";
    BOOL defaultPort = (secure && port == 443) || (!secure && port == 80);
    NSString *host = defaultPort ? url.host : [NSString stringWithFormat:@"%@:%d", url.host, port];
    NSMutableString *request = [NSMutableString stringWithFormat:@"GET %@%@ HTTP/1.1\r\nHost: %@\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                                "Sec-WebSocket-Key: %@\r\nSec-WebSocket-Version: 13\r\n", path, query, host, key];
    if (origin.length) [request appendFormat:@"Origin: %@\r\n", origin];
    if (userAgent.length) [request appendFormat:@"User-Agent: %@\r\n", userAgent];
    [request appendString:@"\r\n"];
    if (![socket writeData:[request dataUsingEncoding:NSUTF8StringEncoding] error:error]) return NO;

    // the answer's header, up to the empty line; whatever follows it already belongs to the frames
    NSMutableData *header = [NSMutableData data];
    uint8_t chunk[2048];
    NSRange end = NSMakeRange(NSNotFound, 0);
    while (end.location == NSNotFound) {
        NSInteger n = [socket readIntoBuffer:chunk maxLength:sizeof(chunk) error:error];
        if (n <= 0) {
            if (n == 0 && error) *error = S6MakeError(S6ErrorConnectionLost, L(@"The server closed the connection without responding."));
            return NO;
        }
        [header appendBytes:chunk length:(NSUInteger)n];
        if (header.length > S6WebSocketMaxHeader) {
            if (error) *error = S6MakeError(S6ErrorBadResponse, L(@"The server sent an invalid response."));
            return NO;
        }
        end = [header rangeOfData:[NSData dataWithBytes:"\r\n\r\n" length:4] options:0 range:NSMakeRange(0, header.length)];
    }
    NSString *head = [[NSString alloc] initWithData:[header subdataWithRange:NSMakeRange(0, end.location)] encoding:NSISOLatin1StringEncoding] ?: @"";
    NSArray *_hlines = [head componentsSeparatedByString:@"\r\n"]; NSString *statusLine = [_hlines count] ? [_hlines objectAtIndex:0] : @"";
    NSArray *parts = [statusLine componentsSeparatedByString:@" "];
    NSInteger status = parts.count > 1 ? [[parts objectAtIndex:1] integerValue] : 0;
    if (status != 101) {
        if (error) *error = S6MakeError(status > 0 ? status : S6ErrorBadResponse, [NSString stringWithFormat:L(@"Unexpected response: %@"), statusLine ?: @""]);
        return NO;
    }
    NSUInteger bodyStart = NSMaxRange(end);
    if (header.length > bodyStart) [_incoming appendData:[header subdataWithRange:NSMakeRange(bodyStart, header.length - bodyStart)]];
    return YES;
}

#pragma mark - Sending

- (BOOL)sendFrame:(uint8_t)opcode payload:(NSData *)payload error:(NSError **)error
{
    NSUInteger length = payload.length;
    NSMutableData *frame = [NSMutableData dataWithCapacity:length + 14];
    uint8_t head[14];
    NSUInteger h = 0;
    head[h++] = 0x80 | opcode;                          // a single, final frame
    if (length < 126) {
        head[h++] = 0x80 | (uint8_t)length;             // (a client always masks)
    } else if (length <= 0xFFFF) {
        head[h++] = 0x80 | 126;
        head[h++] = (uint8_t)(length >> 8);
        head[h++] = (uint8_t)length;
    } else {
        head[h++] = 0x80 | 127;
        for (int i = 7; i >= 0; i--) head[h++] = (uint8_t)((unsigned long long)length >> (8 * i));
    }
    uint8_t mask[4];
    for (int i = 0; i < 4; i++) mask[i] = (uint8_t)(arc4random() % 256);
    memcpy(head + h, mask, 4);
    h += 4;
    [frame appendBytes:head length:h];
    [frame appendData:payload];
    uint8_t *bytes = (uint8_t *)frame.mutableBytes + h;
    for (NSUInteger i = 0; i < length; i++) bytes[i] ^= mask[i % 4];
    [_writeLock lock];
    BOOL ok = [self.socket writeData:frame error:error];
    [_writeLock unlock];
    return ok;
}

- (BOOL)sendText:(NSString *)text error:(NSError **)error
{
    return [self sendFrame:S6OpText payload:[text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data] error:error];
}

#pragma mark - Receiving

// The header of the frame at the start of the buffer: YES and its sizes when the whole frame has arrived
- (BOOL)frameAtStart:(NSUInteger *)headerLength payload:(unsigned long long *)payloadLength masked:(BOOL *)masked
{
    const uint8_t *b = _incoming.bytes;
    NSUInteger n = _incoming.length;
    if (n < 2) return NO;
    BOOL isMasked = (b[1] & 0x80) != 0;
    unsigned long long length = b[1] & 0x7F;
    NSUInteger pos = 2;
    if (length == 126) {
        if (n < 4) return NO;
        length = ((unsigned long long)b[2] << 8) | b[3];
        pos = 4;
    } else if (length == 127) {
        if (n < 10) return NO;
        length = 0;
        for (int i = 0; i < 8; i++) length = (length << 8) | b[2 + i];
        pos = 10;
    }
    if (isMasked) pos += 4;
    if (headerLength) *headerLength = pos;
    if (payloadLength) *payloadLength = length;
    if (masked) *masked = isMasked;
    if (length > S6WebSocketMaxFrame) return YES;   // (reported as an error by the caller)
    return n >= pos + length;
}

- (NSArray *)takeFrames:(BOOL *)closed error:(NSError **)error
{
    NSMutableArray *texts = [NSMutableArray array];
    NSUInteger headerLength = 0;
    unsigned long long payloadLength = 0;
    BOOL masked = NO;
    while ([self frameAtStart:&headerLength payload:&payloadLength masked:&masked]) {
        if (payloadLength > S6WebSocketMaxFrame) {
            if (error) *error = S6MakeError(S6ErrorBadResponse, L(@"The server sent an invalid response."));
            if (closed) *closed = YES;
            return texts;
        }
        const uint8_t *b = _incoming.bytes;
        BOOL fin = (b[0] & 0x80) != 0;
        uint8_t opcode = b[0] & 0x0F;
        NSMutableData *payload = [NSMutableData dataWithBytes:b + headerLength length:(NSUInteger)payloadLength];
        if (masked) {
            const uint8_t *mask = b + headerLength - 4;
            uint8_t *p = payload.mutableBytes;
            for (NSUInteger i = 0; i < payload.length; i++) p[i] ^= mask[i % 4];
        }
        [_incoming replaceBytesInRange:NSMakeRange(0, headerLength + (NSUInteger)payloadLength) withBytes:NULL length:0];

        switch (opcode) {
            case S6OpText:
            case S6OpBinary:
                _message = payload;
                _messageIsText = (opcode == S6OpText);
                break;
            case S6OpContinuation:
                if (_message) [_message appendData:payload];
                break;
            case S6OpPing:
                [self sendFrame:S6OpPong payload:payload error:NULL];
                continue;
            case S6OpPong:
                continue;
            case S6OpClose:
                [self sendFrame:S6OpClose payload:[NSData data] error:NULL];
                if (closed) *closed = YES;
                return texts;
            default:
                continue;
        }
        if (fin && _message) {
            if (_messageIsText) {
                NSString *text = [[NSString alloc] initWithData:_message encoding:NSUTF8StringEncoding];
                if (text) [texts addObject:text];
            }
            _message = nil;
        }
    }
    return texts;
}

- (NSArray *)readMessages:(BOOL *)closed error:(NSError **)error
{
    if (closed) *closed = NO;
    NSArray *ready = [self takeFrames:closed error:error];
    if (ready.count || (closed && *closed)) return ready;
    uint8_t chunk[16384];
    NSError *readError = nil;
    NSInteger n = [self.socket readIntoBuffer:chunk maxLength:sizeof(chunk) error:&readError];
    if (n == 0) {
        if (closed) *closed = YES;
        return [NSArray array];
    }
    if (n < 0) {
        if (readError.code == S6ErrorTimeout) return [NSArray array];   // (nothing complete in time: the caller reads again)
        if (error) *error = readError;
        if (closed) *closed = YES;
        return [NSArray array];
    }
    [_incoming appendBytes:chunk length:(NSUInteger)n];
    return [self takeFrames:closed error:error];
}

#pragma mark - Ending

- (void)cancel
{
    [self.socket cancel];
}

- (void)close
{
    [self.socket close];
    self.socket = nil;
}

@end
