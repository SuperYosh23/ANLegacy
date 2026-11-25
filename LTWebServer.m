#import "LTWebServer.h"
#import "LTLog.h"

#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>
#import <fcntl.h>

@interface LTWebServer ()
@property (nonatomic, assign) int listenSocket;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) NSThread *acceptThread;
@end

@implementation LTWebServer

- (instancetype)init {
    self = (self = [super init]) ? self : nil;
    if (self) {
        _listenSocket = -1;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (BOOL)startOnPort:(NSInteger)port {
    if (self.running) return YES;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        LTLog(@"WEB srv socket failed: %s", strerror(errno));
        return NO;
    }

    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);   // loopback only
    addr.sin_port = htons((uint16_t)port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        LTLog(@"WEB srv bind failed: %s", strerror(errno));
        close(fd);
        return NO;
    }
    if (listen(fd, 16) != 0) {
        LTLog(@"WEB srv listen failed: %s", strerror(errno));
        close(fd);
        return NO;
    }

    // Find the port that was actually assigned when 0 was requested.
    struct sockaddr_in bound;
    socklen_t boundLen = sizeof(bound);
    if (getsockname(fd, (struct sockaddr *)&bound, &boundLen) == 0) {
        self.port = ntohs(bound.sin_port);
    } else {
        self.port = port;
    }

    self.listenSocket = fd;
    self.running = YES;

    self.acceptThread = [[NSThread alloc] initWithTarget:self selector:@selector(acceptLoop) object:nil];
    self.acceptThread.name = @"com.legacymusic.webserver";
    [self.acceptThread start];

    LTLog(@"WEB srv listening on 127.0.0.1:%ld", (long)self.port);
    return YES;
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;
    if (self.listenSocket >= 0) {
        // Shutting the listener down makes the blocking accept() return.
        shutdown(self.listenSocket, SHUT_RDWR);
        close(self.listenSocket);
        self.listenSocket = -1;
    }
    self.acceptThread = nil;
}

#pragma mark - Accept loop

- (void)acceptLoop {
    while (self.running) {
        int client = accept(self.listenSocket, NULL, NULL);
        if (client < 0) {
            if (!self.running) break;
            if (errno == EINTR) continue;
            break;
        }
        // One thread per connection. The web app issues a handful of parallel
        // requests, so this stays small; a pool would only add complexity for no
        // gain at this scale.
        NSThread *thread = [[NSThread alloc] initWithTarget:self
                                                   selector:@selector(handleConnection:)
                                                     object:[NSNumber numberWithInt:client]];
        thread.name = @"com.legacymusic.webserver.conn";
        [thread start];
    }
}

- (void)handleConnection:(NSNumber *)clientNumber {
    int client = [clientNumber intValue];

    // A read timeout, so a connection that opens and says nothing cannot hold
    // a thread open forever.
    struct timeval tv;
    tv.tv_sec = 15;
    tv.tv_usec = 0;
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    NSData *request = [self readRequestFrom:client];
    if (request.length) {
        [self respondToRequest:request onSocket:client];
    }
    close(client);
}

// Reads the request line, the headers and, when there is one, the body.
- (NSData *)readRequestFrom:(int)client {
    NSMutableData *buffer = [NSMutableData data];
    char chunk[4096];
    NSUInteger headerEnd = NSNotFound;

    while (buffer.length < 512 * 1024) {
        ssize_t n = recv(client, chunk, sizeof(chunk), 0);
        if (n <= 0) break;
        [buffer appendBytes:chunk length:(NSUInteger)n];

        if (headerEnd == NSNotFound) {
            NSString *text = [[NSString alloc] initWithData:buffer encoding:NSISOLatin1StringEncoding];
            NSRange split = [text rangeOfString:@"\r\n\r\n"];
            if (split.location != NSNotFound) headerEnd = split.location + split.length;
        }
        if (headerEnd != NSNotFound) {
            // Complete once the declared body length has arrived.
            NSString *text = [[NSString alloc] initWithData:buffer encoding:NSISOLatin1StringEncoding];
            NSUInteger contentLength = [self contentLengthFromHeaders:text];
            if (buffer.length >= headerEnd + contentLength) break;
        }
    }
    return buffer;
}

- (NSUInteger)contentLengthFromHeaders:(NSString *)text {
    NSRange split = [text rangeOfString:@"\r\n\r\n"];
    NSString *head = split.location != NSNotFound
        ? [text substringToIndex:split.location]
        : text;
    for (NSString *line in [head componentsSeparatedByString:@"\r\n"]) {
        if ([[line lowercaseString] hasPrefix:@"content-length:"]) {
            NSString *value = [line substringFromIndex:[@"content-length:" length]];
            return (NSUInteger)[[value stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]] integerValue];
        }
    }
    return 0;
}

#pragma mark - Response

- (void)respondToRequest:(NSData *)request onSocket:(int)client {
    NSString *text = [[NSString alloc] initWithData:request encoding:NSISOLatin1StringEncoding];
    if (!text.length) return;

    NSArray *lines = [text componentsSeparatedByString:@"\r\n"];
    NSString *requestLine = [lines count] ? [lines objectAtIndex:0] : nil;
    if (!requestLine.length) return;

    NSArray *parts = [requestLine componentsSeparatedByString:@" "];
    NSString *method = parts.count > 0 ? [parts objectAtIndex:0] : @"GET";
    NSString *target = parts.count > 1 ? [parts objectAtIndex:1] : @"/";

    NSString *path = target;
    NSString *query = @"";
    NSRange q = [target rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        path = [target substringToIndex:q.location];
        query = [target substringFromIndex:q.location + 1];
    }
    // Percent-decode, since paths and query values carry escapes.
    path = [self percentDecode:path];
    query = [self percentDecode:query];

    NSUInteger headerEnd = [text rangeOfString:@"\r\n\r\n"].location;
    NSData *body = nil;
    if (headerEnd != NSNotFound) {
        NSUInteger bodyStart = headerEnd + 4;
        if (request.length > bodyStart) {
            body = [request subdataWithRange:NSMakeRange(bodyStart, request.length - bodyStart)];
        }
    }

    NSInteger status = 200;
    NSData *response = nil;
    NSString *contentType = nil;

    if ([path hasPrefix:@"/api/"]) {
        id api = self.api;
        if (api && [api respondsToSelector:@selector(handleMethod:path:query:body:status:)]) {
            NSData *result = [api handleMethod:method path:path query:query body:body status:&status];
            response = result;
        }
        contentType = @"application/json; charset=utf-8";
    } else if ([path hasPrefix:@"/audio/"]) {
        // The bytes of a downloaded track, so the web app can play it without
        // a network round trip to YouTube.
        NSString *videoId = [path substringFromIndex:7];
        id provider = self.fileProvider;
        if (provider && [provider respondsToSelector:@selector(fileDataForPath:)]) {
            response = [provider fileDataForPath:videoId];
        }
        if (response) {
            contentType = @"audio/mp4";
        } else {
            status = 404;
            response = [self notFoundBody];
            contentType = @"text/plain; charset=utf-8";
        }
    } else {
        response = [self staticFileForPath:path];
        if (response) {
            contentType = [self contentTypeForPath:path];
        } else {
            status = 404;
            response = [self notFoundBody];
            contentType = @"text/plain; charset=utf-8";
        }
    }

    if (!response) {
        status = 500;
        response = [self errorBody:@"error"];
        contentType = @"application/json; charset=utf-8";
    }

    // Every request is logged. The web app failing silently was the hardest
    // thing to debug - a request that 404s or answers with the wrong shape
    // looks exactly like a request that never happened.
    if ([path hasPrefix:@"/api/"] || [path hasPrefix:@"/audio/"]) {
        LTLog(@"WEBREQ %@ %@ -> %ld (%lu bytes)", method, path, (long)status,
              (unsigned long)response.length);
        // The audio route's answer decides whether the player can play at all,
        // so its body is worth seeing when it says there was no stream.
        if ([path hasPrefix:@"/api/audio/"]) {
            NSString *body = [[NSString alloc] initWithData:response encoding:NSISOLatin1StringEncoding];
            if (body.length > 300) body = [body substringToIndex:300];
            LTLog(@"WEBREQ   body: %@", body);
        }
    }

    [self sendResponse:response
           contentType:contentType
                status:status
               onSocket:client];
}

- (NSData *)staticFileForPath:(NSString *)path {
    if (!self.staticRoot.length) return nil;
    if ([path hasSuffix:@"/"]) path = [path stringByAppendingString:@"index.html"];

    // Refuse anything that tries to climb out of the root.
    if ([path rangeOfString:@".."].location != NSNotFound) return nil;

    NSString *full = [self.staticRoot stringByAppendingPathComponent:[path hasPrefix:@"/"] ? [path substringFromIndex:1] : path];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:full isDirectory:&isDir] || isDir) return nil;

    return [NSData dataWithContentsOfFile:full];
}

- (NSData *)notFoundBody {
    return [@"not found" dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)errorBody:(NSString *)message {
    NSString *json = [NSString stringWithFormat:@"{\"error\":\"%@\"}", message];
    return [json dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)sendResponse:(NSData *)body
         contentType:(NSString *)contentType
              status:(NSInteger)status
             onSocket:(int)client {
    NSString *reason = status == 200 ? @"OK"
                      : status == 404 ? @"Not Found"
                      : status == 500 ? @"Internal Server Error" : @"Error";
    NSString *head = [NSString stringWithFormat:
                      @"HTTP/1.1 %ld %@\r\n"
                      @"Content-Type: %@\r\n"
                      @"Content-Length: %lu\r\n"
                      @"Cache-Control: no-store\r\n"
                      @"Access-Control-Allow-Origin: *\r\n"
                      @"Connection: close\r\n"
                      @"\r\n",
                      (long)status, reason, contentType ?: @"application/octet-stream",
                      (unsigned long)body.length];
    NSData *headData = [head dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *out = [NSMutableData dataWithData:headData];
    [out appendData:body];

    NSUInteger sent = 0;
    while (sent < out.length) {
        ssize_t n = send(client, [out bytes] + sent, out.length - sent, 0);
        if (n <= 0) break;
        sent += (NSUInteger)n;
    }
}

#pragma mark - Helpers

- (NSDictionary *)queryParametersFromString:(NSString *)query {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (!query.length) return params;
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        if (!pair.length) continue;
        NSRange eq = [pair rangeOfString:@"="];
        NSString *key = pair;
        NSString *val = @"";
        if (eq.location != NSNotFound) {
            key = [pair substringToIndex:eq.location];
            val = [pair substringFromIndex:eq.location + 1];
        }
        key = [self percentDecode:key] ?: @"";
        val = [self percentDecode:val] ?: @"";
        if (key.length) [params setObject:val forKey:key];
    }
    return params;
}

- (NSString *)percentDecode:(NSString *)value {
    if (!value.length) return value;
    NSMutableString *out = [NSMutableString stringWithCapacity:value.length];
    const char *bytes = [value UTF8String];
    NSUInteger i = 0;
    NSUInteger len = strlen(bytes);
    while (i < len) {
        if (bytes[i] == '%' && i + 2 < len) {
            char hex[3] = { bytes[i + 1], bytes[i + 2], 0 };
            char *end = NULL;
            long v = strtol(hex, &end, 16);
            if (end && *end == 0) {
                [out appendFormat:@"%C", (unichar)v];
                i += 3;
                continue;
            }
        }
        if (bytes[i] == '+') {
            [out appendString:@" "];
            i++;
            continue;
        }
        [out appendFormat:@"%C", (unichar)bytes[i]];
        i++;
    }
    return out;
}

- (NSString *)contentTypeForPath:(NSString *)path {
    NSString *ext = [[path pathExtension] lowercaseString];
    if ([ext isEqualToString:@"html"]) return @"text/html; charset=utf-8";
    if ([ext isEqualToString:@"js"] || [ext isEqualToString:@"mjs"]) return @"text/javascript; charset=utf-8";
    if ([ext isEqualToString:@"css"]) return @"text/css; charset=utf-8";
    if ([ext isEqualToString:@"json"]) return @"application/json; charset=utf-8";
    if ([ext isEqualToString:@"svg"]) return @"image/svg+xml";
    if ([ext isEqualToString:@"png"]) return @"image/png";
    if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) return @"image/jpeg";
    if ([ext isEqualToString:@"webp"]) return @"image/webp";
    if ([ext isEqualToString:@"ico"]) return @"image/x-icon";
    if ([ext isEqualToString:@"woff2"]) return @"font/woff2";
    if ([ext isEqualToString:@"woff"]) return @"font/woff";
    if ([ext isEqualToString:@"ttf"]) return @"font/ttf";
    if ([ext isEqualToString:@"wav"]) return @"audio/wav";
    if ([ext isEqualToString:@"mp3"]) return @"audio/mpeg";
    if ([ext isEqualToString:@"m4a"]) return @"audio/mp4";
    return @"application/octet-stream";
}

@end
