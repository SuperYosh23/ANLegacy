#import "LTSyncServer.h"
#import "LTLog.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

static NSString * const LTServiceType = @"_anlegacy-sync._tcp.";
static const NSTimeInterval LTSyncIdleTimeout = 120.0;

@interface LTSyncServer () <NSNetServiceDelegate>
@end

@implementation LTSyncServer {
    int _listenFD;
    NSThread *_acceptThread;
    NSThread *_netThread;
    BOOL _stopping;
    NSUInteger _port;
    NSNetService *_service;
}

- (id)init {
    self = [super init];
    if (self) {
        _listenFD = -1;
    }
    return self;
}

- (NSUInteger)port {
    return _port;
}

- (BOOL)start:(NSError **)error {
    if (_listenFD >= 0) return YES; // already running

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:@"LTSync" code:1 userInfo:@{NSLocalizedDescriptionKey: @"socket() failed"}];
        return NO;
    }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = 0;

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 || listen(fd, 4) != 0) {
        close(fd);
        if (error) *error = [NSError errorWithDomain:@"LTSync" code:2 userInfo:@{NSLocalizedDescriptionKey: @"bind/listen failed"}];
        return NO;
    }

    struct sockaddr_in bound;
    socklen_t len = sizeof(bound);
    getsockname(fd, (struct sockaddr *)&bound, &len);
    _port = ntohs(bound.sin_port);
    _listenFD = fd;
    _stopping = NO;

    _acceptThread = [[NSThread alloc] initWithTarget:self selector:@selector(acceptLoop) object:nil];
    [_acceptThread start];

    // Publish Bonjour from a dedicated thread: UIAlertView's modal main-runloop
    // mode starves CommonModes sources on iOS 6, which would stall publication
    // while the "Waiting for Desktop…" alert is up.
    _netThread = [[NSThread alloc] initWithTarget:self selector:@selector(publishServiceLoop) object:nil];
    [_netThread start];

    // Safety net: stop after the idle timeout with no activity.
    __weak LTSyncServer *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(LTSyncIdleTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LTSyncServer *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!strongSelf->_stopping && strongSelf->_listenFD >= 0) {
            LTLog(@"SYNC idle timeout");
            [strongSelf stop];
        }
    });

    LTLog(@"SYNC server listening on port %d", (int)_port);
    return YES;
}

- (void)stop {
    if (_stopping) return;
    _stopping = YES;
    if (_listenFD >= 0) {
        shutdown(_listenFD, SHUT_RDWR);
        close(_listenFD);
        _listenFD = -1;
    }
    // Wake the publish thread so its runloop exits and it can tear down the
    // service from the thread it was scheduled on.
    if (_netThread && !_netThread.finished) {
        [self performSelector:@selector(netThreadNoop) onThread:_netThread withObject:nil waitUntilDone:NO];
    }
    LTLog(@"SYNC server stopped");
}

- (void)netThreadNoop { }

#pragma mark - Bonjour publication

// Runs on _netThread.
- (void)publishServiceLoop {
    @autoreleasepool {
        NSNetService *service = [[NSNetService alloc] initWithDomain:@"" type:LTServiceType name:@"" port:(NSInteger)_port];
        service.delegate = self;
        _service = service;
        [service scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [service publish];
        while (!_stopping) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
        [service removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [service stop];
        _service = nil;
    }
}

- (void)netServiceDidPublish:(NSNetService *)sender {
    LTLog(@"SYNC published %@ port %ld", sender.name.length ? sender.name : @"(unnamed)", (long)sender.port);
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *, NSNumber *> *)errorDict {
    LTLog(@"SYNC publish failed %@", errorDict);
}

#pragma mark - Accept loop

- (void)acceptLoop {
    @autoreleasepool {
        while (!_stopping) {
            int peer = accept(_listenFD, NULL, NULL);
            if (peer < 0) break;
            if (_stopping) { close(peer); break; }
            NSNumber *fdNum = @(peer);
            [self performSelectorInBackground:@selector(handleConnection:) withObject:fdNum];
        }
    }
}

#pragma mark - Connection handling

- (void)handleConnection:(NSNumber *)fdNum {
    @autoreleasepool {
        int fd = fdNum.intValue;
        struct timeval tv = {15, 0};
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

        NSMutableData *buffer = [NSMutableData data];
        NSData *request = [self readRequestIntoBuffer:buffer fd:fd];
        NSString *method = @"", *path = @"";
        NSData *body = nil;
        BOOL parsed = [self parseRequest:request method:&method path:&path body:&body];

        NSInteger status = 500;
        NSData *responseBody = nil;
        if (!parsed) {
            status = 400;
        } else if (self.requestHandler) {
            @try {
                responseBody = self.requestHandler(method, path, body, &status);
                if (status == 0) status = 200;
            } @catch (NSException *e) {
                LTLog(@"SYNC handler exception %@", e);
                status = 500;
            }
        } else {
            status = 404;
        }

        if (!_stopping && self.onConnectionFinished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.onConnectionFinished(method, path);
            });
        }

        NSString *reason = status == 200 ? @"OK" : (status == 400 ? @"Bad Request" : (status == 404 ? @"Not Found" : @"Error"));
        NSMutableString *head = [NSMutableString stringWithFormat:
            @"HTTP/1.1 %ld %@\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
            (long)status, reason, (unsigned long)(responseBody ? responseBody.length : 0)];
        NSData *headData = [head dataUsingEncoding:NSUTF8StringEncoding];

        @try {
            write(fd, headData.bytes, headData.length);
            if (responseBody.length) write(fd, responseBody.bytes, responseBody.length);
        } @catch (NSException *e) { }
        shutdown(fd, SHUT_WR);
        close(fd);
        LTLog(@"SYNC served %@ %@ -> %ld", method, path, (long)status);
    }
}

// Read until we have headers + full Content-Length worth of body.
- (NSData *)readRequestIntoBuffer:(NSMutableData *)buffer fd:(int)fd {
    uint8_t tmp[4096];
    while (buffer.length < (1024 * 1024)) {
        NSRange headerEnd = [buffer rangeOfData:[NSData dataWithBytes:"\r\n\r\n" length:4]
                                        options:0
                                          range:NSMakeRange(0, buffer.length)];
        if (headerEnd.location != NSNotFound) {
            NSInteger contentLength = 0;
            NSString *headerText = [[NSString alloc] initWithData:[buffer subdataWithRange:NSMakeRange(0, headerEnd.location)]
                                                          encoding:NSUTF8StringEncoding];
            for (NSString *line in [headerText componentsSeparatedByString:@"\r\n"]) {
                NSRange colon = [line rangeOfString:@":"];
                if (colon.location == NSNotFound) continue;
                NSString *key = [[line substringToIndex:colon.location] lowercaseString];
                if ([key isEqualToString:@"content-length"]) {
                    contentLength = [[[line substringFromIndex:NSMaxRange(colon)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] integerValue];
                }
            }
            NSUInteger have = buffer.length - NSMaxRange(headerEnd);
            if (have >= (NSUInteger)contentLength) break;
        }
        ssize_t n = read(fd, tmp, sizeof(tmp));
        if (n <= 0) break;
        [buffer appendBytes:tmp length:(NSUInteger)n];
    }
    return buffer;
}

- (BOOL)parseRequest:(NSData *)data method:(NSString **)method path:(NSString **)path body:(NSData **)body {
    NSRange headerEnd = [data rangeOfData:[NSData dataWithBytes:"\r\n\r\n" length:4] options:0 range:NSMakeRange(0, data.length)];
    if (headerEnd.location == NSNotFound) return NO;
    NSString *headerText = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, headerEnd.location)] encoding:NSUTF8StringEncoding];
    if (!headerText.length) return NO;

    NSArray *lines = [headerText componentsSeparatedByString:@"\r\n"];
    NSString *requestLine = [lines count] ? [lines objectAtIndex:0] : @"";
    NSArray *parts = [requestLine componentsSeparatedByString:@" "];
    if (parts.count < 2) return NO;
    *method = parts[0];
    *path = parts[1];

    NSInteger contentLength = 0;
    for (NSString *line in lines) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *key = [[line substringToIndex:colon.location] lowercaseString];
        if ([key isEqualToString:@"content-length"]) {
            contentLength = [[[line substringFromIndex:NSMaxRange(colon)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] integerValue];
        }
    }
    NSUInteger available = data.length - NSMaxRange(headerEnd);
    NSUInteger take = MIN((NSUInteger)contentLength, available);
    *body = take ? [data subdataWithRange:NSMakeRange(NSMaxRange(headerEnd), take)] : [NSData data];
    return YES;
}

@end
