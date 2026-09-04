#import "LTP2PSync.h"
#import "LTSyncServer.h"
#import "LTPlaylistStore.h"
#import "LTLog.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <unistd.h>

// Phone-to-phone sync over the local Wi-Fi network. Each phone publishes a
// Bonjour server AND browses for the other phone's server (both advertise the
// same service type). Whichever phone finds a peer connects to it as an HTTP
// client, POSTs its own payload, and the server merges it and returns the full
// local payload in the response; the client merges that too. No desktop or LAN
// server is involved — the phones talk directly to each other.

static NSString *const LTP2PServiceType = @"_anlegacy-p2p._tcp.";
static NSMutableArray *LTP2PActiveSyncs;

// Minimal HTTP client over a BSD socket (blocking, run on a background thread).
@interface LTP2PHTTPClient : NSObject
- (NSData *)postPayload:(NSData *)payload toHost:(NSString *)host port:(NSUInteger)port error:(NSError **)error;
@end

@interface LTP2PSync () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property (nonatomic, strong) LTSyncServer *server;
@property (nonatomic, strong) NSNetServiceBrowser *browser;
@property (nonatomic, strong) NSMutableArray *resolvingServices;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, strong) UIAlertView *statusAlert;
@property (nonatomic, assign) BOOL sentOurPayload;
@property (nonatomic, assign) BOOL finished;
@end

@implementation LTP2PSync

+ (void)initialize {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ LTP2PActiveSyncs = [NSMutableArray array]; });
}

+ (BOOL)isSyncing {
    return LTP2PActiveSyncs.count > 0;
}

+ (void)beginFromViewController:(UIViewController *)presenter {
    if (LTP2PActiveSyncs.count) return;
    LTP2PSync *sync = [[LTP2PSync alloc] init];
    [LTP2PActiveSyncs addObject:sync];
    [sync beginWithPresenter:presenter];
}

- (NSMutableArray *)resolvingServices {
    if (!_resolvingServices) _resolvingServices = [NSMutableArray array];
    return _resolvingServices;
}

- (void)beginWithPresenter:(UIViewController *)presenter {
    self.presenter = presenter;

    // 1) Serve our own library on a Bonjour-published local TCP server.
    self.server = [[LTSyncServer alloc] init];
    self.server.serviceType = LTP2PServiceType;
    __weak LTP2PSync *weakSelf = self;
    self.server.requestHandler = ^NSData *(NSString *method, NSString *path, NSData *body, NSInteger *status) {
        LTP2PSync *strongSelf = weakSelf;
        if (!strongSelf) { *status = 500; return nil; }
        NSError *err = nil;
        if ([method isEqualToString:@"POST"] && [path hasPrefix:@"/api/merge"]) {
            NSDictionary *incoming = [NSJSONSerialization JSONObjectWithData:body options:0 error:&err];
            if (![incoming isKindOfClass:[NSDictionary class]]) { *status = 400; return nil; }
            if ([strongSelf versionMismatchInPayload:incoming]) {
                *status = 409; // Conflict: version mismatch
                return [strongSelf versionErrorJSON];
            }
            // Replay this phone's PRE-merge state to the peer. The peer merges
            // it (summing combined stats) and we merge the peer's raw payload
            // here, so each phone's numbers are added exactly once.
            NSDictionary *preMerge = [[LTPlaylistStore sharedStore] syncPayload];
            [[LTPlaylistStore sharedStore] mergeSyncPayload:incoming];
            [strongSelf markCompletedOnMain];
            NSMutableDictionary *reply = [NSMutableDictionary dictionaryWithDictionary:preMerge];
            reply[@"appVersion"] = [strongSelf appVersion];
            NSData *json = [NSJSONSerialization dataWithJSONObject:reply options:0 error:&err];
            *status = 200;
            return json ?: nil;
        }
        *status = 404;
        return nil;
    };
    __weak LTP2PSync *weakSelf2 = self;
    self.server.onConnectionFinished = ^(NSString *method, NSString *path) {
        (void)weakSelf2;
    };
    NSError *error = nil;
    if (![self.server start:&error]) {
        [self finish];
        [self showFailure:error.localizedDescription ?: @"Could not start peer sync."];
        return;
    }

    // 2) Browse for the peer's server.
    self.browser = [[NSNetServiceBrowser alloc] init];
    self.browser.delegate = self;
    [self.browser searchForServicesOfType:LTP2PServiceType inDomain:@"local."];

    // Fail-safe: if we never find a peer within 30s, tell the user (they may
    // have the other phone off or in another network).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LTP2PSync *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.finished) return;
        [strongSelf finish];
        [strongSelf showFailure:@"Could not find another phone. Make sure both phones are on the same Wi-Fi network and that you pressed \"Sync with Another Phone\" on both."];
    });

    [self showStatus:@"Waiting for Another Phone…"
             message:@"Press \"Sync with Another Phone\" on your second phone. Both phones must be on the same Wi-Fi network."];
}

#pragma mark - Version compatibility

- (NSString *)appVersion {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] ?: @"";
}

- (BOOL)versionMismatchInPayload:(NSDictionary *)payload {
    NSString *remote = payload[@"appVersion"];
    if (![remote isKindOfClass:[NSString class]]) remote = @"";
    return ![remote isEqualToString:[self appVersion]];
}

- (NSData *)versionErrorJSON {
    NSDictionary *body = @{@"error": @"version_mismatch",
                           @"required": [self appVersion]};
    return [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
}

#pragma mark - Completion / UI

- (void)finish {
    [self.browser stop];
    self.browser.delegate = nil;
    self.browser = nil;
    // Stop resolving any in-flight services.
    for (NSNetService *s in self.resolvingServices) {
        s.delegate = nil;
    }
    [self.resolvingServices removeAllObjects];
    [self.server stop];
    self.server = nil;
    [self dismissStatus];
    [LTP2PActiveSyncs removeObject:self];
}

- (void)markCompletedOnMain {
    if (self.finished) return;
    self.finished = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self finish];
        [self showDoneAlert];
    });
}

- (void)showStatus:(NSString *)title message:(NSString *)message {
    if (self.statusAlert) {
        self.statusAlert.title = title;
        self.statusAlert.message = message;
        return;
    }
    self.statusAlert = [[UIAlertView alloc] initWithTitle:title
                                                  message:message
                                                 delegate:self
                                        cancelButtonTitle:@"Cancel"
                                        otherButtonTitles:nil];
    [self.statusAlert show];
}

- (void)dismissStatus {
    [self.statusAlert dismissWithClickedButtonIndex:-1 animated:NO];
    self.statusAlert = nil;
}

- (void)showDoneAlert {
    NSString *title = @"Library Synced";
    NSString *message = @"Playlists, library, recent songs and listening stats from both phones are now on both phones.";
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)showFailure:(NSString *)reason {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Sync Failed"
                                                    message:reason.length ? reason : @"Could not connect to the other phone."
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
            didFindService:(NSNetService *)service moreComing:(BOOL)more {
    // Resolve it to learn its host + port, then connect as a client.
    service.delegate = self;
    [self.resolvingServices addObject:service];
    [service resolveWithTimeout:10.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
            didNotSearch:(NSDictionary *)errorDict {
    LTLog(@"P2P browse failed %@", errorDict);
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    NSString *host = [self addressStringForService:sender];
    NSInteger port = sender.port;
    if (!host.length) {
        [self.resolvingServices removeObject:sender];
        return;
    }
    // A phone browsing for the sync service ALSO discovers its OWN published
    // service. Syncing with ourselves would merge our own stats into a
    // self-referential "received" ledger (inflating the totals) and never reach
    // the peer. Skip any service that resolves to one of this device's own
    // addresses.
    if ([self isLocalAddress:host]) {
        [self.resolvingServices removeObject:sender];
        return;
    }
    [self.resolvingServices removeObject:sender];
    [self postOurPayloadToHost:host port:(NSUInteger)port];
}

- (BOOL)isLocalAddress:(NSString *)host {
    if (!host.length) return NO;
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return NO;
    BOOL isLocal = NO;
    for (struct ifaddrs *ifaddr = interfaces; ifaddr && !isLocal; ifaddr = ifaddr->ifa_next) {
        if (!ifaddr->ifa_addr) continue;
        if (ifaddr->ifa_addr->sa_family != AF_INET) continue;
        const struct sockaddr_in *in4 = (const struct sockaddr_in *)ifaddr->ifa_addr;
        char buf[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &in4->sin_addr, buf, sizeof(buf))) {
            if ([host isEqualToString:[NSString stringWithUTF8String:buf]]) {
                isLocal = YES;
            }
        }
    }
    freeifaddrs(interfaces);
    return isLocal;
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
    [self.resolvingServices removeObject:sender];
    LTLog(@"P2P resolve failed %@", errorDict);
}

- (NSString *)addressStringForService:(NSNetService *)service {
    for (NSData *addrData in service.addresses) {
        const struct sockaddr *addr = addrData.bytes;
        if (addr->sa_family == AF_INET) {
            const struct sockaddr_in *in4 = (const struct sockaddr_in *)addr;
            char buf[INET_ADDRSTRLEN];
            if (inet_ntop(AF_INET, &in4->sin_addr, buf, sizeof(buf))) {
                return [NSString stringWithUTF8String:buf];
            }
        }
    }
    return nil;
}

- (void)postOurPayloadToHost:(NSString *)host port:(NSUInteger)port {
    NSDictionary *payload = [[LTPlaylistStore sharedStore] syncPayload];
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:payload];
    m[@"appVersion"] = [self appVersion];
    NSData *body = [NSJSONSerialization dataWithJSONObject:m options:0 error:nil];
    if (!body) return;

    // Network I/O on a background thread so the main queue (and the status
    // alert) stays responsive.
    __weak LTP2PSync *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        LTP2PSync *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSError *error = nil;
        NSData *response = [[LTP2PHTTPClient new] postPayload:body toHost:host port:port error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (!strongSelf.finished) {
                    LTLog(@"P2P POST failed: %@", error);
                }
                return;
            }
            NSDictionary *merged = [NSJSONSerialization JSONObjectWithData:response options:0 error:nil];
            if (![merged isKindOfClass:[NSDictionary class]]) {
                [strongSelf finishAndFail:@"The other phone sent back an invalid response."];
                return;
            }
            if ([strongSelf versionMismatchInPayload:merged]) {
                [strongSelf finishAndFail:[NSString stringWithFormat:@"The other phone is running a different app version. Both phones must run the same version (you: %@).", [strongSelf appVersion]]];
                return;
            }
            [[LTPlaylistStore sharedStore] mergeSyncPayload:merged];
            if (!strongSelf.finished) {
                strongSelf.finished = YES;
                [strongSelf finish];
                [strongSelf showDoneAlert];
            }
        });
    });
}

- (void)finishAndFail:(NSString *)reason {
    if (self.finished) return;
    self.finished = YES;
    [self finish];
    [self showFailure:reason];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 0) [self finish]; // user cancelled while waiting
}

@end

#pragma mark - LTP2PHTTPClient

@implementation LTP2PHTTPClient

- (NSData *)postPayload:(NSData *)payload toHost:(NSString *)host port:(NSUInteger)port error:(NSError **)outError {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (outError) *outError = [NSError errorWithDomain:@"LTP2P" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"socket() failed"}];
        return nil;
    }
    struct timeval tv = {20, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, [host UTF8String], &addr.sin_addr) != 1) {
        close(fd);
        if (outError) *outError = [NSError errorWithDomain:@"LTP2P" code:1002 userInfo:@{NSLocalizedDescriptionKey: @"bad host"}];
        return nil;
    }

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd);
        if (outError) *outError = [NSError errorWithDomain:@"LTP2P" code:1003 userInfo:@{NSLocalizedDescriptionKey: @"connect failed"}];
        return nil;
    }

    NSData *header = [[NSString stringWithFormat:
        @"POST /api/merge HTTP/1.1\r\nHost: %@\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
        host, (unsigned long)payload.length] dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableData *request = [NSMutableData data];
    [request appendData:header];
    [request appendData:payload];

    const uint8_t *bytes = request.bytes;
    size_t total = request.length, sent = 0;
    while (sent < total) {
        ssize_t n = write(fd, bytes + sent, total - sent);
        if (n <= 0) {
            close(fd);
            if (outError) *outError = [NSError errorWithDomain:@"LTP2P" code:1004 userInfo:@{NSLocalizedDescriptionKey: @"write failed"}];
            return nil;
        }
        sent += (size_t)n;
    }

    // Read the full HTTP response body (parse Content-Length).
    NSMutableData *response = [NSMutableData data];
    uint8_t tmp[4096];
    NSInteger contentLength = -1;
    BOOL headersDone = NO;
    NSRange headerEndRange = NSMakeRange(NSNotFound, 0);
    NSUInteger bodyStart = 0;

    while (response.length < (8 * 1024 * 1024)) {
        ssize_t n = read(fd, tmp, sizeof(tmp));
        if (n <= 0) break;
        [response appendBytes:tmp length:(NSUInteger)n];

        if (!headersDone) {
            NSRange r = [response rangeOfData:[NSData dataWithBytes:"\r\n\r\n" length:4]
                                      options:0
                                        range:NSMakeRange(0, response.length)];
            if (r.location != NSNotFound) {
                headersDone = YES;
                headerEndRange = r;
                bodyStart = NSMaxRange(r);
                NSString *head = [[NSString alloc] initWithData:[response subdataWithRange:NSMakeRange(0, r.location)]
                                                       encoding:NSUTF8StringEncoding];
                for (NSString *line in [head componentsSeparatedByString:@"\r\n"]) {
                    NSRange colon = [line rangeOfString:@":"];
                    if (colon.location == NSNotFound) continue;
                    NSString *key = [[line substringToIndex:colon.location] lowercaseString];
                    if ([key isEqualToString:@"content-length"]) {
                        contentLength = [[[line substringFromIndex:NSMaxRange(colon)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] integerValue];
                    }
                }
            }
        }
        if (headersDone && contentLength >= 0) {
            NSUInteger have = response.length - bodyStart;
            if (have >= (NSUInteger)contentLength) break;
        }
    }

    close(fd);

    if (!headersDone) {
        if (outError) *outError = [NSError errorWithDomain:@"LTP2P" code:1005 userInfo:@{NSLocalizedDescriptionKey: @"no response"}];
        return nil;
    }
    NSUInteger available = response.length - bodyStart;
    NSUInteger take = (contentLength >= 0) ? MIN((NSUInteger)contentLength, available) : available;
    return [response subdataWithRange:NSMakeRange(bodyStart, take)];
}

@end